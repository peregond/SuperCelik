#ifndef SUPER_CELIK_CARD_IO_H
#define SUPER_CELIK_CARD_IO_H

#include "document_card.h"

typedef struct {
    sc_card_transmit transmit;
    void *context;
} sc_card_channel;

sc_card_result sc_select_application(sc_card_channel card, const uint8_t *aid,
                                     size_t aid_length, uint8_t p2);
sc_card_result sc_select_file(sc_card_channel card, uint16_t id, uint8_t p1, uint8_t p2);
sc_card_result sc_read_range(sc_card_channel card, uint8_t *file, size_t offset, size_t end);

#endif
