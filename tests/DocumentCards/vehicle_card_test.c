#include "vehicle_card.h"

#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

/* Synthetic group A, based on the public tag specification. No cardholder data. */
static const uint8_t group_a[] = {
    0x78, 7, 0x4f, 5, 0xf9, 0x11, 0x22, 0x33, 0x44,
    0x71, 0x81, 53,
    0x9f, 0x37, 1, 1,
    0x81, 7, 'T', 'S', '1', '2', '3', 'X', 'X',
    0x8a, 17, 'T', 'E', 'S', 'T', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '1',
    0xa3, 9, 0x87, 2, 0xb0, 0xd2, 0x89, 3, 'T', 'S', 'T',
    0x82, 8, '2', '0', '2', '4', '0', '2', '2', '9'
};

typedef struct {
    unsigned phase;
    unsigned expected_offset;
    bool unknown;
    bool repeated_response;
    bool interrupted;
} fake_card;

static int transmit(void *context, const uint8_t *apdu, size_t length,
                    uint8_t *response, size_t capacity, size_t *received)
{
    fake_card *card = context;
    assert(apdu[0] == 0);
    unsigned status = 0x9000;
    size_t n = 0;
    if (apdu[1] == 0xa4) {
        assert(!card->expected_offset);
        if (card->unknown) status = 0x6a82;
        else {
            if (card->phase < 3) {
                assert(apdu[2] == 4 && length == (size_t)apdu[4] + 5);
                assert(apdu[3] == (card->phase == 2 ? 0x0c : 0));
                if (card->phase == 0) status = 0x6102;
            } else {
                assert(length == 7 && memcmp(apdu, "\x00\xa4\x02\x04\x02\xd0\x01", 7) == 0);
            }
        }
        ++card->phase;
    } else if (apdu[1] == 0xc0) {
        assert(length == 5 && card->phase == 1 && apdu[4] == 2);
        if (card->repeated_response) status = 0x6102;
        else { n = 2; response[0] = 0x6f; response[1] = 0; }
    } else {
        assert(apdu[1] == 0xb0 && length == 5 && card->phase == 4);
        if (card->interrupted) return 1;
        size_t offset = (size_t)apdu[2] << 8 | apdu[3];
        n = apdu[4];
        assert(offset == card->expected_offset && n && n <= sizeof(group_a) - offset);
        memcpy(response, group_a + offset, n);
        card->expected_offset += (unsigned)n;
    }
    assert(n + 2 <= capacity);
    response[n] = (uint8_t)(status >> 8);
    response[n + 1] = (uint8_t)status;
    *received = n + 2;
    return 0;
}

int main(void)
{
    sc_vehicle_document document;
    assert(sc_vehicle_decode(group_a, sizeof(group_a), &document) == SC_CARD_OK);
    assert(strcmp(document.registration, "TS123XX") == 0);
    assert(strcmp(document.vin, "TEST0000000000001") == 0);
    assert(strcmp(document.make, "\xd0\x90\xd0\xb2") == 0);
    assert(strcmp(document.model, "TST") == 0);
    assert(strcmp(document.first_registration_date, "20240229") == 0);
    assert(!document.valid_until_on_card[0]);
    for (size_t i = 0; i < sizeof(group_a); ++i) {
        assert(sc_vehicle_decode(group_a, i, &document) == SC_CARD_BAD_DATA);
        assert(!document.registration[0]);
    }
    uint8_t bad_date[sizeof(group_a)];
    memcpy(bad_date, group_a, sizeof(bad_date));
    bad_date[sizeof(bad_date) - 5] = '3';
    assert(sc_vehicle_decode(bad_date, sizeof(bad_date), &document) == SC_CARD_BAD_DATA);
    fake_card card = {0};
    assert(sc_vehicle_read(transmit, &card, &document) == SC_CARD_OK);
    assert(card.expected_offset == sizeof(group_a));
    assert(strcmp(document.registration, "TS123XX") == 0);
    card = (fake_card){.unknown = true};
    assert(sc_vehicle_read(transmit, &card, &document) == SC_CARD_UNRECOGNIZED);
    assert(card.phase == 3 && !document.registration[0]);
    card = (fake_card){.repeated_response = true};
    assert(sc_vehicle_read(transmit, &card, &document) == SC_CARD_READER_ERROR);
    assert(!document.registration[0]);
    card = (fake_card){.interrupted = true};
    assert(sc_vehicle_read(transmit, &card, &document) == SC_CARD_READER_ERROR);
    assert(!document.registration[0]);
    puts("Vehicle card parser and read-only exchange passed");
}
