# Vehicle registration and KZO card prototypes

The portable readers accept an existing contact smart-card connection through a callback. The vehicle reader decodes the registration number, VIN, make, model and dates from group A. The KZO reader decodes the holder's name and LBO from the fixed personal data block. Both report what is on the chip. A successful read does not verify the signature or the current status of the registration or insurance.

The vehicle implementation uses [Annex I of Directive 2003/127/EC](https://eur-lex.europa.eu/eli/dir/2003/127/oj) and the [Serbian MUP SDK](https://www.mup.gov.rs/wps/wcm/connect/da87fe51-6fa6-49e2-a5cd-74c889861ee3/SaobracajnaApi.zip?MOD=AJPERES&CVID=kTXD3Ru). KZO protocol facts were checked against the official [RFZO WCS package](https://rfzo.rs/osiguranalica/ekartica/kzo-down), version 1.3.4. The prototype has no runtime dependency on either binary.

From the repository root, run the synthetic exchange and decoder tests:

```sh
for kind in vehicle health; do
  cc -std=c11 -Wall -Wextra -Werror -I Sources/DocumentCards \
    Sources/DocumentCards/card_io.c "Sources/DocumentCards/${kind}_card.c" \
    "tests/DocumentCards/${kind}_card_test.c" -o "/tmp/supercelik-${kind}-test" || break
  "/tmp/supercelik-${kind}-test" || break
done
```

On macOS with one contact reader connected, build the hardware probe:

```sh
cc -std=c11 -Wall -Wextra -Werror -Wno-deprecated-declarations \
  -I Sources/DocumentCards Sources/DocumentCards/*.c \
  tests/DocumentCards/card_pcsc_probe.c -framework PCSC \
  -o /tmp/super-celik-card-check
/tmp/super-celik-card-check vehicle  # or health, according to the inserted card
```

The probe opens the first reader exclusively for a short session. It prints only the selected test, result and, on a read error, protocol status codes. It never prints a field from the chip or an APDU payload. Verify success on physical cards before exposing either reader in the app. Both are prototypes, outside the application flows.
