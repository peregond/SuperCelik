# Notes for App Review (paste into App Store Connect → App Review Information → Notes)

**What the app does.** Super Celik reads a Serbian electronic ID card / foreigner ID / residence permit and shows, prints
and shares its data. Everything happens on the device; the app has no accounts, no server and no analytics.

**You do not need a Serbian card to review.** Open **Settings (gear icon, top right) → "Show demo data"**: the app then shows
a fictional person, the signature check result, the PDF printout (View PDF / Print / Share) and the Token tab. No sign-in is required.

**Reading a real card** needs a Serbian eID card and either a smart card reader (USB-C / Lightning) or an NFC-capable card
on an iPhone. iPad has no NFC reader, so on iPad the app explains that and works with demo data and USB readers only.
NFC is used only when the user taps "Read card"; the usage description is in Info.plist.

**Not affiliated.** The app is an independent implementation and says so in its description and About text. It does not use
any MUP RS or NetSeT/Veridos code, logo or trademark. "Super Celik" is a working name; we will rename it on request.

**Encryption / export compliance.** The app only verifies digital signatures and hashes (standard OS frameworks);
`ITSAppUsesNonExemptEncryption` is `false`.

**Privacy.** No data collected (see the privacy policy URL and the privacy manifest in the bundle).

Contact: (fill in your name, phone and e-mail in App Store Connect)
