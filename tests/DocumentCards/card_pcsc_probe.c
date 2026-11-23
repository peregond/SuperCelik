#include "vehicle_card.h"
#include "health_card.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __APPLE__
#include <PCSC/winscard.h>
typedef uint32_t pcsc_size;
#else
#ifdef _WIN32
#include <windows.h>
#endif
#include <winscard.h>
typedef DWORD pcsc_size;
#endif

#ifdef _WIN32
#define list_readers SCardListReadersA
#define connect_card SCardConnectA
#else
#define list_readers SCardListReaders
#define connect_card SCardConnect
#endif

typedef struct {
    SCARDHANDLE handle;
    pcsc_size protocol;
    uint32_t reader_result;
    unsigned card_status;
    uint8_t command;
} session;

static int transmit(void *context, const uint8_t *command, size_t length,
                    uint8_t *response, size_t capacity, size_t *received)
{
    session *card = context;
    SCARD_IO_REQUEST protocol = {card->protocol, sizeof(protocol)};
    pcsc_size count = (pcsc_size)capacity;
    card->command = command[1];
    card->reader_result = (uint32_t)SCardTransmit(card->handle, &protocol, command,
                                                (pcsc_size)length, NULL, response, &count);
    if (card->reader_result != SCARD_S_SUCCESS || count < 2 || count > capacity) return 1;
    card->card_status = (unsigned)response[count - 2] << 8 | response[count - 1];
    *received = (size_t)count;
    return 0;
}

int main(int argc, char *argv[])
{
    if (argc != 2 || (strcmp(argv[1], "vehicle") != 0 && strcmp(argv[1], "health") != 0)) {
        fputs("Usage: super-celik-card-check vehicle|health\n", stderr);
        return 2;
    }
    printf("Super Čelik card check, prototype 1. Type: %s.\n", argv[1]);
    SCARDCONTEXT context;
    if (SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &context) != SCARD_S_SUCCESS) {
        fputs("Smart card service unavailable.\n", stderr);
        return 1;
    }
    int exit_status = 1;
    char *readers = NULL;
    pcsc_size length = 0;
    if (list_readers(context, NULL, NULL, &length) != SCARD_S_SUCCESS || length < 2) {
        puts("No PC/SC reader detected.");
        goto done;
    }
    readers = calloc(length, sizeof(*readers));
    if (!readers || list_readers(context, NULL, readers, &length) != SCARD_S_SUCCESS || !readers[0]) {
        puts("Reader list unavailable.");
        goto done;
    }
    session card = {0};
    if (connect_card(context, readers, SCARD_SHARE_EXCLUSIVE, SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1,
                     &card.handle, &card.protocol) != SCARD_S_SUCCESS) {
        puts("Could not open a card in the first reader.");
        goto done;
    }
    sc_card_result status;
    if (strcmp(argv[1], "vehicle") == 0) {
        sc_vehicle_document document;
        status = sc_vehicle_read(transmit, &card, &document);
    } else {
        sc_health_document document;
        status = sc_health_read(transmit, &card, &document);
    }
    SCardDisconnect(card.handle, SCARD_LEAVE_CARD);
    if (status == SC_CARD_OK) {
        puts("Read successful. No card details were printed.");
        exit_status = 0;
    } else {
        printf("Read failed. Result %d, command %02X, status %04X, reader status %08X.\n",
               (int)status, (unsigned)card.command, card.card_status, (unsigned)card.reader_result);
    }
done:
    free(readers);
    SCardReleaseContext(context);
    return exit_status;
}
