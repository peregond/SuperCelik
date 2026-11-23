#ifndef SUPER_CELIK_VEHICLE_CARD_H
#define SUPER_CELIK_VEHICLE_CARD_H

#include "document_card.h"

typedef struct {
    char registration[41];
    char vin[201];
    char make[201];
    char model[201];
    char first_registration_date[9]; /* YYYYMMDD */
    char issue_date[9];
    char valid_until_on_card[9];
} sc_vehicle_document;

/* Decode the public registration data (group A). Output strings are UTF-8.
   This reports chip contents only. It does not attest to the signature or
   to current registration status. The output is cleared on failure. */
sc_card_result sc_vehicle_decode(const uint8_t *file, size_t length,
                                    sc_vehicle_document *document);

/* Read group A through an existing contact smart-card session. Only SELECT,
   READ BINARY and GET RESPONSE can be sent. The output is cleared on failure. */
sc_card_result sc_vehicle_read(sc_card_transmit transmit, void *context,
                                  sc_vehicle_document *document);

#endif
