#include "health_card.h"
#include "card_io.h"

#include <stdbool.h>
#include <string.h>

/* Fixed personal block in the RFZO KZO format. Only this block is needed to
   display the holder's name and LBO. No PIN, signature or network calls. */
#define PERSONAL_FILE 0x0d02u
#define MAX_FILE 4096u
#define HEADER 4u
#define INSURANCE_NUMBER 0x0621u
#define SURNAME 0x0622u
#define SURNAME_LATIN 0x0623u
#define GIVEN_NAME 0x0624u
#define GIVEN_NAME_LATIN 0x0625u

typedef struct {
    const uint8_t *data;
    size_t length;
} field;

static unsigned little_word(const uint8_t *data)
{
    return (unsigned)data[1] << 8 | data[0];
}

static bool append_utf8(unsigned scalar, char *destination, size_t capacity, size_t *used)
{
    const unsigned size = scalar < 0x80 ? 1 : scalar < 0x800 ? 2 : scalar < 0x10000 ? 3 : 4;
    if (size >= capacity - *used) return false;
    static const unsigned prefix[] = {0, 0, 0xc0, 0xe0, 0xf0};
    char *output = destination + *used;
    for (unsigned i = size - 1; i; --i) {
        output[i] = (char)(0x80 | (scalar & 0x3f));
        scalar >>= 6;
    }
    output[0] = (char)(prefix[size] | scalar);
    *used += size;
    return true;
}

static bool copy_name(field value, char *out, size_t capacity)
{
    if ((value.length & 1u) || value.length > 100) return false;
    while (value.length && little_word(value.data + value.length - 2) == 0) value.length -= 2;
    size_t used = 0, i = 0;
    if (value.length && little_word(value.data) == 0xfeff) i = 2;
    while (i < value.length) {
        unsigned scalar = little_word(value.data + i);
        i += 2;
        if (scalar >= 0xd800 && scalar <= 0xdbff) {
            if (i == value.length) return false;
            unsigned low = little_word(value.data + i);
            if (low < 0xdc00 || low > 0xdfff) return false;
            scalar = 0x10000 + ((scalar - 0xd800) << 10) + (low - 0xdc00);
            i += 2;
        } else if ((scalar >= 0xdc00 && scalar <= 0xdfff) || scalar == 0xfffe || scalar == 0xffff) {
            return false;
        }
        if (scalar < 0x20 || (scalar >= 0x7f && scalar <= 0x9f)) return false;
        if (!append_utf8(scalar, out, capacity, &used)) return false;
    }
    while (used && out[used - 1] == ' ') --used;
    out[used] = '\0';
    return true;
}

sc_card_result sc_health_decode(const uint8_t *file, size_t length, sc_health_document *document)
{
    if (!document) return SC_CARD_BAD_DATA;
    memset(document, 0, sizeof(*document));
    if (!file || length < HEADER || length > MAX_FILE || little_word(file) != PERSONAL_FILE ||
        little_word(file + 2) != length - HEADER) return SC_CARD_BAD_DATA;

    field fields[5] = {0};
    size_t offset = HEADER;
    while (offset < length) {
        if (length - offset < HEADER) return SC_CARD_BAD_DATA;
        unsigned tag = little_word(file + offset);
        size_t size = little_word(file + offset + 2);
        offset += HEADER;
        if (size > length - offset) return SC_CARD_BAD_DATA;
        if (tag >= INSURANCE_NUMBER && tag <= GIVEN_NAME_LATIN) {
            field *entry = fields + (tag - INSURANCE_NUMBER);
            if (entry->data) return SC_CARD_BAD_DATA;
            *entry = (field){file + offset, size};
        }
        offset += size;
    }

    sc_health_document parsed = {0};
    field lbo = fields[0];
    if (lbo.length != sizeof(parsed.insurance_number) - 1) return SC_CARD_BAD_DATA;
    for (size_t i = 0; i < lbo.length; ++i)
        if (lbo.data[i] < '0' || lbo.data[i] > '9') return SC_CARD_BAD_DATA;
    memcpy(parsed.insurance_number, lbo.data, lbo.length);
    field surname = fields[SURNAME_LATIN - INSURANCE_NUMBER];
    field given = fields[GIVEN_NAME_LATIN - INSURANCE_NUMBER];
    if (!copy_name(surname, parsed.surname, sizeof(parsed.surname)) ||
        !copy_name(given, parsed.given_name, sizeof(parsed.given_name))) return SC_CARD_BAD_DATA;
    if (!parsed.surname[0] &&
        !copy_name(fields[SURNAME - INSURANCE_NUMBER], parsed.surname, sizeof(parsed.surname))) return SC_CARD_BAD_DATA;
    if (!parsed.given_name[0] &&
        !copy_name(fields[GIVEN_NAME - INSURANCE_NUMBER], parsed.given_name, sizeof(parsed.given_name))) return SC_CARD_BAD_DATA;
    if (!parsed.surname[0] || !parsed.given_name[0]) return SC_CARD_BAD_DATA;
    *document = parsed;
    return SC_CARD_OK;
}

sc_card_result sc_health_read(sc_card_transmit transmit, void *context, sc_health_document *document)
{
    if (!document) return SC_CARD_BAD_DATA;
    memset(document, 0, sizeof(*document));
    if (!transmit) return SC_CARD_READER_ERROR;
    sc_card_channel card = {transmit, context};
    /* Published RFZO middleware has distinct ISO 7816 AIDs for the two
       applications it supports. Select only these, never by guessing from ATR. */
    static const uint8_t coverage[] = {0xf3, 0x81, 0, 0, 2, 'S', 'E', 'R', 'V', 'S', 'Z', 'K', 1};
    static const uint8_t legacy[] = {0xf3, 0x81, 0, 0, 2, 'S', 'E', 'R', 'S', 'O', 'V', 'O', 'Z', 'K', 1};
    sc_card_result status = sc_select_application(card, coverage, sizeof(coverage), 0);
    if (status == SC_CARD_UNRECOGNIZED) status = sc_select_application(card, legacy, sizeof(legacy), 0);
    if (status != SC_CARD_OK) return status;
    status = sc_select_file(card, PERSONAL_FILE, 0, 0);
    if (status != SC_CARD_OK) return status;
    uint8_t file[MAX_FILE];
    status = sc_read_range(card, file, 0, HEADER);
    if (status != SC_CARD_OK) return status;
    size_t length = HEADER + little_word(file + 2);
    if (little_word(file) != PERSONAL_FILE || length > MAX_FILE) return SC_CARD_BAD_DATA;
    status = sc_read_range(card, file, HEADER, length);
    if (status != SC_CARD_OK) return status;
    return sc_health_decode(file, length, document);
}
