# Notes for App Review (paste into App Store Connect → App Review Information → Notes)

**What the app does.** Super Čelik reads a Serbian electronic ID card / foreigner ID / residence permit and shows, prints
and shares its data. Everything happens on the device; the app has no accounts, no server and no analytics.

**You do not need a Serbian card to review.** Open **Settings (third tab in the bottom bar) → "Show demo data"**: the app then shows
a fictional person, the signature check result, the PDF printout (View PDF / Print / Share) and the Token tab. No sign-in is required.

**Reading a real card** needs a Serbian eID card and a smart card reader connected over USB-C (or an MFi reader). The app
shows at once whether a reader is connected and whether a card is inserted. The app does not use NFC
(NFC reading is switched off and the bundle has no NFC entitlement). Reader support was tested on iPhone and iPad.

**Not affiliated.** The app is an independent implementation and says so in its description and About text. It does not use
any MUP RS or NetSeT/Veridos code, logo or trademark. "Super Čelik" is a working name; we will rename it on request.

**Encryption / export compliance.** The app only verifies digital signatures and hashes (standard OS frameworks);
`ITSAppUsesNonExemptEncryption` is `false`.

**Privacy.** No data collected (privacy policy: https://celik.peregon.cc/privacy; see also the privacy manifest in the bundle).

Contact: (fill in your name, phone and e-mail in App Store Connect)
