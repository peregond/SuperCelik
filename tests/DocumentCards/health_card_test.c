#include "health_card.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

/* Fabricated LBO and names, encoded as the documented fixed personal block. */
static const uint8_t block[] = {
    0x02, 0x0d, 39, 0,
    0x21, 0x06, 11, 0, '0','0','0','0','0','0','0','0','0','0','0',
    0x22, 0x06, 6, 0, 0xff, 0xfe, 0x1f, 0x04, 0x35, 0x04,
    0x23, 0x06, 2, 0, 0x07, 0x01,
    0x24, 0x06, 4, 0, 0x09, 0x04, 0x43, 0x04
};

typedef struct {
    unsigned calls;
    unsigned accepted_app;
    unsigned stop_at;
    int corrected_length;
} fake_reader;

static int reply(void *context, const uint8_t *command, size_t length,
                 uint8_t *out, size_t capacity, size_t *received)
{
    fake_reader *reader = context;
    unsigned step = ++reader->calls, status = 0x9000;
    size_t data = 0;
    assert(command[0] == 0);
    if (step == reader->stop_at) return 1;
    if (step == 1) {
        static const uint8_t aid[] = {0xf3,0x81,0,0,2,'S','E','R','V','S','Z','K',1};
        assert(length == sizeof(aid) + 5 && command[1] == 0xa4 && command[2] == 4);
        assert(command[3] == 0 && command[4] == sizeof(aid) && memcmp(command + 5, aid, sizeof(aid)) == 0);
        if (reader->accepted_app != 1) status = 0x6a82;
    } else if (step == 2 && reader->accepted_app != 1) {
        static const uint8_t aid[] = {0xf3,0x81,0,0,2,'S','E','R','S','O','V','O','Z','K',1};
        assert(length == sizeof(aid) + 5 && command[1] == 0xa4 && command[2] == 4);
        assert(command[3] == 0 && command[4] == sizeof(aid) && memcmp(command + 5, aid, sizeof(aid)) == 0);
        if (reader->accepted_app != 2) status = 0x6a82;
    } else if (step == reader->accepted_app + 1) {
        assert(length == 7 && memcmp(command, "\x00\xa4\x00\x00\x02\x0d\x02", 7) == 0);
    } else {
        assert(command[1] == 0xb0 && length == 5);
        size_t offset = (size_t)command[2] << 8 | command[3];
        if (offset == 0 && !reader->corrected_length) {
            status = 0x6c04;
            reader->corrected_length = 1;
        } else {
            data = command[4];
            assert(offset < sizeof(block) && data <= sizeof(block) - offset && capacity >= data + 2);
            memcpy(out, block + offset, data);
        }
    }
    assert(data + 2 <= capacity);
    out[data] = (uint8_t)(status >> 8);
    out[data + 1] = (uint8_t)status;
    *received = data + 2;
    return 0;
}

int main(void)
{
    sc_health_document document;
    assert(sc_health_decode(block, sizeof(block), &document) == SC_CARD_OK);
    assert(strcmp(document.insurance_number, "00000000000") == 0);
    assert(strcmp(document.surname, "\xc4\x87") == 0);
    assert(strcmp(document.given_name, "\xd0\x89\xd1\x83") == 0);
    for (size_t i = 0; i < sizeof(block); ++i) {
        assert(sc_health_decode(block, i, &document) == SC_CARD_BAD_DATA);
        assert(!document.given_name[0] && !document.insurance_number[0]);
    }
    uint8_t invalid[sizeof(block)];
    memcpy(invalid, block, sizeof(block));
    invalid[8] = 'X';
    assert(sc_health_decode(invalid, sizeof(invalid), &document) == SC_CARD_BAD_DATA);
    memcpy(invalid, block, sizeof(block));
    invalid[sizeof(invalid) - 1] = 0xd8;
    assert(sc_health_decode(invalid, sizeof(invalid), &document) == SC_CARD_BAD_DATA);
    for (unsigned application = 1; application <= 2; ++application) {
        fake_reader reader = {.accepted_app = application};
        assert(sc_health_read(reply, &reader, &document) == SC_CARD_OK);
        assert(reader.calls == application + 4 && reader.corrected_length);
        assert(strcmp(document.insurance_number, "00000000000") == 0);
    }
    fake_reader reader = {0};
    assert(sc_health_read(reply, &reader, &document) == SC_CARD_UNRECOGNIZED);
    assert(!document.insurance_number[0] && reader.calls == 2);
    reader = (fake_reader){.accepted_app = 1, .stop_at = 5};
    assert(sc_health_read(reply, &reader, &document) == SC_CARD_READER_ERROR);
    assert(!document.given_name[0] && !document.insurance_number[0]);
    puts("KZO parser and read-only exchange passed");
}
