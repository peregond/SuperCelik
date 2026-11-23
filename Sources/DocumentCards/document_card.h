#ifndef SUPER_CELIK_DOCUMENT_CARD_H
#define SUPER_CELIK_DOCUMENT_CARD_H

#include <stddef.h>
#include <stdint.h>

/* Send one APDU. Set the returned length (including SW1/SW2), or return
   nonzero on a reader error. The callback must respect the response capacity. */
typedef int (*sc_card_transmit)(void *context, const uint8_t *command,
                                   size_t command_length, uint8_t *response,
                                   size_t capacity, size_t *response_length);

typedef enum {
    SC_CARD_OK,
    SC_CARD_UNRECOGNIZED,
    SC_CARD_READER_ERROR,
    SC_CARD_COMMAND_ERROR,
    SC_CARD_BAD_DATA
} sc_card_result;

#endif
