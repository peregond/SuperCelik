# Features on every system

The base is one list of functions. Every system offers all of them; only the platform part (how the card reaches the
browser, how updates arrive) differs. When a function is added, it goes into this table and into every column the same
release, or the cell says why it cannot.

| Function | Windows | Linux | macOS | iOS | Android |
|---|---|---|---|---|---|
| Read the ID card (data, photo) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Verify the card signature | ✅ | ✅ | ✅ | ✅ | ✅ |
| Read a vehicle registration card (saobraćajna dozvola) on the "Card" tab; one Read button for every card. **Parsed from the EU / MUP specifications, not yet checked on a real card**; the issuer signature is not verified | ✅ | ✅ | ✅ | ✅ USB reader only (the NFC application name is not confirmed) | ✅ |
| Print / save the vehicle registration card as a PDF (a plain one-page table) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Card diagnostics: structure of any card, no personal data, no PIN (hidden: tap the version 5 times in Settings; `--diag` on Windows and Linux). Its log is copied with a button | ✅ | ✅ | ✅ | ✅ | ✅ |
| Read the health insurance card (KZO) | – not yet | – not yet | – not yet | – not yet | – not yet |
| Print / save the PDF | ✅ | ✅ | ✅ | ✅ | ✅ |
| Hide sensitive fields (mask) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Read the token (certificates), export `.cer` | ✅ | ✅ | ✅ | ✅ | ✅ |
| Change PIN, unblock with PUK | ✅ | ✅ | ✅ | ✅ | ✅ |
| Sign a file (`.p7s`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Sign in to eUprava | ✅ | ✅ | ✅ | ✅ | ✅ (in the app) |
| Set up and check browser sign-in (one button) | ✅ driver + Firefox | ✅ module | ✅ driver (automatic) | – | – |
| "No reader yet?" page | ✅ | ✅ | ✅ | ✅ | ✅ |
| "What's new?" page | ✅ | ✅ | ✅ | ✅ | ✅ |
| Report a bug / leave feedback | ✅ | ✅ | ✅ | ✅ | ✅ |
| Demo data (Settings switch) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Copy logs and errors (Settings) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Language: ru, en, sr (Latin, Cyrillic), hu, sq, sk, ro, hr, uk, be; theme | ✅ | ✅ | ✅ | ✅ | ✅ |
| Auto-read when the card is inserted | ✅ | ✅ | ✅ | ✅ | ✅ (reader already connected) |
| Hide the data after idle time | ✅ | ✅ | ✅ | – (not wanted) | – (not wanted) |
| Check for updates inside the app | ✅ | ✅ | ✅ (not the App Store build) | – (App Store) | – (store / APK page) |

"– not yet" on the health card: no official description of its chip exists and its protocol is not known; the diagnostics above are there to find it out on a real card, and nothing is added until a log shows that the data is readable without a service card.

"–" is not a gap to fill: a phone has no browser to set up, and apps from a store are updated by the store.
Idle hide is not wanted on iOS and Android (the data goes with the app); every other cell is filled.

Where the code lives:

- **Shared C#** (Windows and Linux compile the same files): card access, crypto, texts (`windows/SerbiaID.Windows/Loc.cs`).
- **Shared Swift** (macOS and iOS): `Sources/SerbiaID`, texts in `Localization.swift`.
- **Android**: Kotlin, texts in `res/values*/strings.xml`.
- The site page `site/changelog/index.html` lists every change per system; each release has a block with the new number.
