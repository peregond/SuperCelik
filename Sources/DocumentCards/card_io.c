#include "card_io.h"

#include <stdbool.h>
#include <string.h>

#define READ_CHUNK 128u

static bool exchange(sc_card_channel card, const uint8_t *command, size_t length, bool has_le,
                     uint8_t *data, size_t capacity, size_t *received, unsigned *status)
{
    uint8_t apdu[32], response[258];
    if (length > sizeof(apdu)) return false;
    memcpy(apdu, command, length);
    *received = 0;
    for (unsigned attempts = 0; attempts < 16; ++attempts) {
        size_t n = 0;
        if (card.transmit(card.context, apdu, length, response, sizeof(response), &n) ||
            n < 2 || n > sizeof(response)) return false;
        uint8_t sw1 = response[n - 2], sw2 = response[n - 1];
        if (sw1 == 0x6c && has_le) {
            apdu[length - 1] = sw2;
            continue;
        }
        n -= 2;
        if (n > capacity - *received) return false;
        memcpy(data + *received, response, n);
        *received += n;
        *status = (unsigned)sw1 << 8 | sw2;
        if (sw1 != 0x61) return true;
        const uint8_t get_response[] = {0, 0xc0, 0, 0, sw2};
        memcpy(apdu, get_response, sizeof(get_response));
        length = sizeof(get_response);
        has_le = true;
    }
    return false;
}

sc_card_result sc_select_application(sc_card_channel card, const uint8_t *aid, size_t aid_length, uint8_t p2)
{
    uint8_t select[21] = {0, 0xa4, 4, p2, (uint8_t)aid_length};
    uint8_t data[256];
    size_t n;
    unsigned status;
    memcpy(select + 5, aid, aid_length);
    if (!exchange(card, select, 5 + aid_length, false, data, sizeof(data), &n, &status))
        return SC_CARD_READER_ERROR;
    if (status == 0x9000) return SC_CARD_OK;
    /* Keep transport and security failures distinct from an unknown application. */
    if (status == 0x6a82 || status == 0x6a86 || status == 0x6d00)
        return SC_CARD_UNRECOGNIZED;
    return SC_CARD_COMMAND_ERROR;
}

/* Read an exact range in small chunks. */
sc_card_result sc_read_range(sc_card_channel card, uint8_t *file, size_t offset, size_t end)
{
    while (offset < end) {
        size_t left = end - offset;
        uint8_t count = (uint8_t)(left < READ_CHUNK ? left : READ_CHUNK);
        const uint8_t read[] = {0, 0xb0, (uint8_t)(offset >> 8), (uint8_t)offset, count};
        size_t n;
        unsigned status;
        if (!exchange(card, read, sizeof(read), true, file + offset, left, &n, &status))
            return SC_CARD_READER_ERROR;
        if (status != 0x9000) return SC_CARD_COMMAND_ERROR;
        if (!n || n > count) return SC_CARD_BAD_DATA;
        offset += n;
    }
    return SC_CARD_OK;
}

sc_card_result sc_select_file(sc_card_channel card, uint16_t id, uint8_t p1, uint8_t p2)
{
    const uint8_t select[] = {0, 0xa4, p1, p2, 2, (uint8_t)(id >> 8), (uint8_t)id};
    uint8_t control[256];
    size_t length;
    unsigned status;
    if (!exchange(card, select, sizeof(select), false, control, sizeof(control), &length, &status))
        return SC_CARD_READER_ERROR;
    return status == 0x9000 ? SC_CARD_OK : SC_CARD_COMMAND_ERROR;
}
