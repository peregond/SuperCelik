#ifndef SUPER_CELIK_HEALTH_CARD_H
#define SUPER_CELIK_HEALTH_CARD_H

#include "document_card.h"

typedef struct {
    char insurance_number[12]; /* LBO, including leading zeroes */
    char given_name[151];
    char surname[151];
} sc_health_document;

/* Decode the local fixed personal data block. The names are UTF-8. The output
   is cleared on failure. A successful read says nothing about insurance status. */
sc_card_result sc_health_decode(const uint8_t *file, size_t length, sc_health_document *document);
sc_card_result sc_health_read(sc_card_transmit transmit, void *context, sc_health_document *document);

#endif
