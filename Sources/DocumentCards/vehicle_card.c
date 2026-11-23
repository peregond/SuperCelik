#include "vehicle_card.h"
#include "card_io.h"

#include <stdbool.h>
#include <string.h>

#define MAX_FILE 4096u

typedef struct {
    const uint8_t *data;
    size_t length;
} bytes;

typedef struct {
    unsigned tag;
    bytes value;
} tlv;

/* Annex I of 2003/127/EC and the MUP eVehicle Registration SDK define the
   data format. Accept only bounded definite-length BER-TLV objects. */
static bool next_tlv(bytes *input, tlv *item)
{
    if (input->length < 2) return false;
    size_t offset = 1;
    unsigned tag = input->data[0];
    if ((tag & 0x1fu) == 0x1f) {
        if (input->length < 3 || (input->data[offset] & 0x7fu) == 0) return false;
        uint8_t part = input->data[offset++];
        tag = tag << 8 | part;
        if (part & 0x80u) {
            if (input->length <= offset + 1 || input->data[offset] & 0x80u) return false;
            tag = tag << 8 | input->data[offset++];
        }
    }
    size_t length = input->data[offset++];
    if (length & 0x80u) {
        size_t count = length & 0x7fu;
        if (!count || count > 2 || count > input->length - offset) return false;
        length = 0;
        while (count--) length = length << 8 | input->data[offset++];
    }
    if (length > input->length - offset) return false;
    *item = (tlv){tag, {input->data + offset, length}};
    input->data += offset + length;
    input->length -= offset + length;
    return true;
}

static bool get_tag(bytes input, unsigned tag, bytes *value)
{
    *value = (bytes){0};
    while (input.length) {
        tlv item;
        if (!next_tlv(&input, &item)) return false;
        if (item.tag != tag) continue;
        if (value->data) return false;
        *value = item.value;
    }
    return true;
}

static unsigned latin_or_cyrillic(uint8_t c, bool cyrillic)
{
    if (!cyrillic || c <= 0xa0) return c;
    if (c == 0xad) return 0xad;
    if (c == 0xf0) return 0x2116;
    if (c == 0xfd) return 0xa7;
    return 0x0400u + c - 0xa0u;
}

static bool copy_text(bytes input, unsigned alphabet, char *out, size_t capacity)
{
    while (input.length && (input.data[input.length - 1] == ' ' ||
                            input.data[input.length - 1] == 0)) --input.length;
    size_t used = 0;
    for (size_t i = 0; i < input.length; ++i) {
        uint8_t c = input.data[i];
        if (c < 0x20 || (c >= 0x7f && c < 0xa0) || (c >= 0xa0 && alphabet > 1)) return false;
        unsigned scalar = latin_or_cyrillic(c, alphabet == 1);
        if (scalar < 0x80 && used + 1 < capacity) {
            out[used++] = (char)scalar;
        } else if (scalar >= 0x80 && scalar < 0x800 && used + 2 < capacity) {
            out[used++] = (char)(0xc0 | scalar >> 6);
            out[used++] = (char)(0x80 | (scalar & 0x3f));
        } else if (scalar >= 0x800 && used + 3 < capacity) {
            out[used++] = (char)(0xe0 | scalar >> 12);
            out[used++] = (char)(0x80 | (scalar >> 6 & 0x3f));
            out[used++] = (char)(0x80 | (scalar & 0x3f));
        } else {
            return false;
        }
    }
    out[used] = '\0';
    return true;
}

static bool copy_date(bytes input, char out[9])
{
    if (!input.length) return true;
    if (input.length != 8) return false;
    for (size_t i = 0; i < input.length; ++i)
        if (input.data[i] < '0' || input.data[i] > '9') return false;
    if (memcmp(input.data, "00000000", 8) == 0) return true;
    unsigned year = 0;
    for (size_t i = 0; i < 4; ++i) year = year * 10 + input.data[i] - '0';
    unsigned month = (input.data[4] - '0') * 10u + input.data[5] - '0';
    unsigned day = (input.data[6] - '0') * 10u + input.data[7] - '0';
    static const unsigned days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    if (!year || month < 1 || month > 12 || !day) return false;
    bool leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    if (day > days[month - 1] + (month == 2 && leap)) return false;
    memcpy(out, input.data, 8);
    return true;
}

sc_card_result sc_vehicle_decode(const uint8_t *file, size_t length,
                                    sc_vehicle_document *document)
{
    if (!document) return SC_CARD_BAD_DATA;
    memset(document, 0, sizeof(*document));
    if (!file || length > MAX_FILE) return SC_CARD_BAD_DATA;
    bytes input = {file, length};
    tlv authority, data;
    if (!next_tlv(&input, &authority) || authority.tag != 0x78 ||
        !next_tlv(&input, &data) || data.tag != 0x71) return SC_CARD_BAD_DATA;
    for (size_t i = 0; i < input.length; ++i)
        if (input.data[i] != 0) return SC_CARD_BAD_DATA;
    bytes card_application;
    if (!get_tag(authority.value, 0x4f, &card_application) ||
        card_application.length < 5 || card_application.length > 16) return SC_CARD_BAD_DATA;

    bytes encoding, registration, vin, vehicle, make, model, first, issue, expiry;
    if (!get_tag(data.value, 0x9f37, &encoding) ||
        !get_tag(data.value, 0x81, &registration) ||
        !get_tag(data.value, 0x8a, &vin) ||
        !get_tag(data.value, 0xa3, &vehicle) ||
        !get_tag(vehicle, 0x87, &make) || !get_tag(vehicle, 0x89, &model) ||
        !get_tag(data.value, 0x82, &first) || !get_tag(data.value, 0x8e, &issue) ||
        !get_tag(data.value, 0x8d, &expiry)) return SC_CARD_BAD_DATA;
    unsigned alphabet = 0;
    if (encoding.data) {
        if (encoding.length == 1 && encoding.data[0] <= 2) alphabet = encoding.data[0];
        else if (encoding.length == 2 && encoding.data[0] == '0' &&
                 encoding.data[1] >= '0' && encoding.data[1] <= '2') alphabet = encoding.data[1] - '0';
        else return SC_CARD_BAD_DATA;
    }
    sc_vehicle_document parsed = {0};
    if (!copy_text(registration, alphabet, parsed.registration, sizeof(parsed.registration)) ||
        !copy_text(vin, alphabet, parsed.vin, sizeof(parsed.vin)) ||
        !copy_text(make, alphabet, parsed.make, sizeof(parsed.make)) ||
        !copy_text(model, alphabet, parsed.model, sizeof(parsed.model)) ||
        !copy_date(first, parsed.first_registration_date) || !copy_date(issue, parsed.issue_date) ||
        !copy_date(expiry, parsed.valid_until_on_card) || !parsed.registration[0] || !parsed.vin[0])
        return SC_CARD_BAD_DATA;
    *document = parsed;
    return SC_CARD_OK;
}

static sc_card_result select_registration(sc_card_channel card)
{
    /* Compatibility identifiers observed in the MUP SDK. These are on-card
       identifiers. Some cards require a parent application to be selected first. */
    static const uint8_t series1[] = {0xa0, 0, 0, 1, 0x51, 0, 0};
    static const uint8_t series2[] = {0xa0, 0, 0, 0, 3, 0, 0, 0};
    static const uint8_t series3[] = {0xa0, 0, 0, 0, 0x18, 0x43, 0x4d, 0};
    static const uint8_t middle1[] = {0xa0, 0, 0, 0, 0x77, 1, 8, 0, 7, 0, 0, 0xfe, 0, 0, 1, 0};
    static const uint8_t middle2[] = {0xf3, 0x81, 0, 0, 2, 'S', 'E', 'R', 'V', 'L', 4, 2, 1};
    static const uint8_t middle3[] = {0xa0, 0, 0, 0, 0x18, 0x34, 0x14, 1, 0, 'e', 'V', 'L', '-', '0', '0', '1'};
    static const uint8_t registration[] = {0xa0, 0, 0, 0, 0x77, 1, 8, 0, 7, 0, 0, 0xfe, 0, 0, 0xad, 0xf2};
    static const uint8_t registration3[] = {0xa0, 0, 0, 0, 0x18, 'e', 'V', 'L', '-', '0', '0', '1'};
    static const struct { bytes parent, middle, app; } profiles[] = {
        {{series1, sizeof(series1)}, {middle1, sizeof(middle1)}, {registration, sizeof(registration)}},
        {{series2, sizeof(series2)}, {middle2, sizeof(middle2)}, {registration, sizeof(registration)}},
        {{series3, sizeof(series3)}, {middle3, sizeof(middle3)}, {registration3, sizeof(registration3)}}
    };
    for (size_t i = 0; i < sizeof(profiles) / sizeof(profiles[0]); ++i) {
        bytes parent = profiles[i].parent, middle = profiles[i].middle, app = profiles[i].app;
        sc_card_result result = sc_select_application(card, parent.data, parent.length, 0);
        if (result == SC_CARD_UNRECOGNIZED) continue;
        if (result != SC_CARD_OK) return result;
        result = sc_select_application(card, middle.data, middle.length, 0);
        if (result == SC_CARD_UNRECOGNIZED) continue;
        if (result != SC_CARD_OK) return result;
        result = sc_select_application(card, app.data, app.length, 0x0c);
        if (result != SC_CARD_UNRECOGNIZED) return result;
    }
    return SC_CARD_UNRECOGNIZED;
}

static sc_card_result read_object(sc_card_channel card, uint8_t *file, size_t *offset, uint8_t tag)
{
    size_t start = *offset;
    if (start > MAX_FILE - 2) return SC_CARD_BAD_DATA;
    size_t value_start = start + 2;
    sc_card_result result = sc_read_range(card, file, start, value_start);
    if (result != SC_CARD_OK) return result;
    if (file[start] != tag) return SC_CARD_BAD_DATA;
    size_t length = file[start + 1];
    if (length & 0x80u) {
        size_t extra = length & 0x7fu;
        if (!extra || extra > 2 || extra > MAX_FILE - value_start) return SC_CARD_BAD_DATA;
        result = sc_read_range(card, file, value_start, value_start + extra);
        if (result != SC_CARD_OK) return result;
        length = 0;
        while (extra--) length = length << 8 | file[value_start++];
    }
    if (length > MAX_FILE - value_start) return SC_CARD_BAD_DATA;
    *offset = value_start + length;
    return sc_read_range(card, file, value_start, *offset);
}

sc_card_result sc_vehicle_read(sc_card_transmit transmit, void *context,
                                  sc_vehicle_document *document)
{
    if (!document) return SC_CARD_BAD_DATA;
    memset(document, 0, sizeof(*document));
    if (!transmit) return SC_CARD_READER_ERROR;
    sc_card_channel card = {transmit, context};
    sc_card_result selected = select_registration(card);
    if (selected != SC_CARD_OK) return selected;
    uint8_t file[MAX_FILE];
    sc_card_result file_status = sc_select_file(card, 0xd001, 2, 4);
    if (file_status != SC_CARD_OK) return file_status;
    size_t offset = 0;
    sc_card_result result = read_object(card, file, &offset, 0x78);
    if (result != SC_CARD_OK) return result;
    result = read_object(card, file, &offset, 0x71);
    if (result != SC_CARD_OK) return result;
    return sc_vehicle_decode(file, offset, document);
}
