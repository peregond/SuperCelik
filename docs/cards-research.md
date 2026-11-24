# Research: vehicle registration card and health insurance card

Status: **specification-level only.** Nothing below has been confirmed on a real card yet.
Items marked **[SPEC]** come from an official document, **[UNKNOWN]** are not published anywhere we may use,
**[CARD]** must be established by our own diagnostic mode on a real card.

Rule for this work: nothing is taken from third-party open-source readers (bas-celik, jevrc, jfreesteel and the like).
Sources used: EU directives, documents published by MUP RS and RFZO, ISO/IEC 7816.

## Sources

| Source | What we took from it |
|---|---|
| [Directive 1999/37/EC, Annex I, Chapter III](https://www.legislation.gov.uk/eudr/1999/37/annexes/data.xht) as amended by [2003/127/EC](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32003L0127) | Smart card format: file list, file IDs, BER-TLV tags, character set, dates, access rules, how to read |
| MUP RS, [Читач електронске саобраћајне дозволе](https://www.mup.gov.rs/wps/wcm/connect/public_cyrillic/pocetna/gradjani/dokumenti+gradjana/registracija+vozila/citac+elektronske+saobracajne+dozvole): package "API Saobraćajne" (`SaobracajnaApi.zip`) | Two PDFs: "Podaci u čipu SD" (field list with EU codes, sizes) and "eVehicle Registration SDK, Korisničko uputstvo" (July 2011: field-to-tag table, file IDs, behaviour). Only the PDFs were read; the DLLs in the package were not opened or run |
| RFZO, [Начин провере валидности картице](https://rfzo.rs/osiguranalica/ekartica/nacinproverekartice), [Секција за преузимање](https://rfzo.rs/osiguranalica/ekartica/kzo-down), [Изглед и подаци на КЗО](https://rfzo.rs/osiguranalica/ekartica/ekartica-podaci-menu), technical instructions for "КЗО Читач" 3.0.0 (PDF linked from the download page) | What the card holds, what the official reader does, what it needs |

## 1. Vehicle registration card (Саобраћајна дозвола)

### Application and files
- Application "Vehicle Registration", selected by **SELECT by DF name (AID)**. **[SPEC]** The directive says the AID is issued by a laboratory chosen by the Commission. **[UNKNOWN]** The AID is not printed in the directive or in the MUP documents. **[CARD]** has to find it (see "Open questions").
- Files are transparent EFs, selected with SELECT (P1=02, P2=04, data = file ID) inside the application; the FCP in the answer gives the size; then READ BINARY with a short Le. **[SPEC]**
- Files, from the directive and the MUP SDK table: **[SPEC]**

| Data file | Signature file | Issuer certificate file | Content |
|---|---|---|---|
| EF.Registration_A `D001` | `E001` | `C001` | Part 1, mandatory data, template `71` |
| EF.Registration_B `D011` | `E011` | `C011` | Optional data, template `72` (user, category, axles, engine number, colour) |
| EF.Registration_C `D021` | `E021` | `C021` | Serbian extension (national group), signed (MUP SDK) |
| a fourth file, unsigned | — | — | Mentioned by the MUP SDK as "per the domestic specification, not signed". ID **[UNKNOWN]** |

- Size limits implied by the MUP SDK buffers: data ≤ 4096 bytes, signature ≤ 1024, certificate ≤ 4096. Files are zero-padded; the SDK strips the padding. **[SPEC]**

### Encoding
- BER-TLV. The outer template `78` holds `4F` (AID); the data template follows (`71` or `72`; `73`/`74` are Part II of a two-part certificate and are not expected on a single-part card). **[SPEC]**
- Values are ASCII; bytes C0–FF are ISO 8859-1, -5 (Cyrillic) or -7 (Greek), chosen by tag `9F37` (`00` Latin-1, `01` Cyrillic, `02` Greek). Dates are `YYYYMMDD`. **[SPEC]** Which character set Serbian cards use is **[CARD]**.
- Tags used by the MUP SDK (EU tag, or "extension" for national ones): **[SPEC]**

| Meaning | Tag | EU form code |
|---|---|---|
| State / competent authority / issuing authority / document number | `9F33` / `9F35` / `9F36` / `9F38` | — |
| Registration number | `81` | A |
| Date of first registration | `82` | B |
| Owner surname or company, name, address | `A1 > A7 > 83 / 84 / 85` | C.1.1–C.1.3 |
| User surname or company, name, address | `A1 > A9 > 83 / 84 / 85` | C.3.1–C.3.3 |
| Make, type, commercial name | `A3 > 87 / 88 / 89` | D.1–D.3 |
| VIN | `8A` | E |
| Max permissible laden mass / vehicle mass | `A4 > 8B` / `8C` | F.1 / G |
| Validity / date of this registration | `8D` / `8E` | H / I |
| Type approval number | `8F` | K |
| Engine capacity / power / fuel | `A5 > 90 / 91 / 92` (the SDK table writes `5A`, see below) | P.1–P.3 |
| Power/weight (motorcycles) | `93` | Q |
| Seats / standing places | `A6 > 94 / 95` | S.1 / S.2 |
| Category | `98` | J |
| Axles | `99` | L |
| Engine number | `A5 > 9E` (SDK: `5A`) | P.5 |
| Colour | `9F24` | R |
| National extension: sale ban until / owner personal no. / user personal no. / load / year of production / document serial number | `C1` / `C2` / `C3` / `C4` / `C5` / `C9` | — |

- Discrepancy: the directive nests engine data under `A5`; the MUP SDK table writes `5A`. A typo in one of them or a national variant. The parser must accept both. **[CARD]**
- Which of the national tags sit in `D021` and which in the unsigned file is **[CARD]**.
- Sensitive fields: owner and user name, address and personal number (JMBG, tags `C2`/`C3`), VIN. Masked in the UI like the ID card; never written to the diagnostic log.

### Protection
- "There are no read restrictions on these files." Writing needs asymmetric authentication with the issuing authority's security module. **[SPEC]** The MUP SDK has no PIN parameter anywhere: reading takes only a reader. **[SPEC]** Not seen on a card yet.
- Authenticity: the issuer signs the complete content of each data file; signature in `E0xx`, issuer X.509v3 certificate in `C0xx`. The SDK says the signature file holds a raw signature with no ASN.1 wrapper; the algorithm and hash are **[UNKNOWN]**. Signature checking is a later step; the first version shows data with a "not verified" mark.

### MUP's own reader
MUP offers a Windows reader (32-bit COM/DLL SDK over PC/SC, 2011) with the functions `sdStartup`, `SelectReader`, `sdProcessNewCard` (connects, selects the application, caches file structure), `sdReadDocumentData`, `sdReadVehicleData`, `sdReadPersonalData`, `sdReadRegistration(index 1..3)`. It confirms the flow: select application, read three signed files plus certificates.

## 2. Health insurance card (Здравствена картица, КЗО)

What the sources say, and do not say:
- The card is read by RFZO's "КЗО Читач" 3.0.0: a C# desktop program (.NET 8, Windows x64) over PC/SC. It needs the vendor middleware **TrustEdge** and **nstwcs** (Web Client Services, a COM component). **[SPEC]** This is the same family of middleware as for the ID card, so the card may use the same chip platform. Not established.
- Data on the chip (RFZO page, rule book "Правилник о исправи о здравственом осигурању"): name, surname, JMBG, LBO (insurance number), address, home RFZO branch, premium payer, certification period and other administrative data. No data on care received or prescriptions. **[SPEC]**
- Printed on the card: name, birth date, LBO, card number.
- The reader reads the chip automatically when the card is inserted. A separate button "Провери осигурање" queries an **RFZO SOAP web service over HTTPS** and updates the field "Оверена до". **[SPEC]** The instructions mention no PIN and no service card for either step.
- **The four-digit PIN from the task is not mentioned in any RFZO document found.** Whether the chip needs a PIN for some fields is **[CARD]**. Our diagnostic mode will record the status words of each read.
- File structure, AID and tags: **[UNKNOWN]**. No official document describes them; the middleware hides them. Everything has to come from the card with our own code.
- The SOAP service: no public WSDL or interface description was found, it sends the personal numbers to a server, and the app's promise is "card data never leaves your device". **Not planned.** The app would show only the chip data and the "certified until" date as stored on the chip, if present.

## Open questions for diagnostic mode
1. Registration card: find the AID. **Candidates from the binary of MUP's own `eVehicleRegistrationAPI.dll` (v1.3.2, 2013; opened as data, never run; approved by the project owner as an extra source, not part of the official documents).** A table of byte strings in the DLL contains: `F3 81 00 00 02 53 45 52 56 4C ...` (the Serbian prefix `F381000002` used by the ID-card applets, then ASCII `SERVL`; the bytes after `SERVL` read `04 02 01`, but how the table is delimited is not clear, so the exact AID length and suffix are **not** established). By analogy with the ID card (`F381000002` + `SERID` + `01`) the application name is probably `SERVL` plus a suffix. Other entries in the same table: `A0000000183414010065564C2D303031`, `A00000001865564C2D303031` (ASCII `eVL-001`) and `A000000018434D00` (a GlobalPlatform card-manager style name), plus two `A000000077010800070000FE000001..` values; these may be card-management identifiers, not the application. **[CARD]** Diagnostic mode tries them as full AIDs and as a prefix select (`F381000002534552564C`, partial match) and logs the answers. Fallback: the ATR and a listing from the MF.
2. Registration card: files `D001`/`D011`/`D021`/`E0xx`/`C0xx` present? Sizes? Character set tag? The fourth file's ID?
3. Health card: does a SELECT of the known ID-card and PKCS#15 AIDs succeed? What does the card expose without PIN?
4. For both: status word of every command, so we can see where a PIN or authentication is demanded.

## Implementation status (version 1.6.0)
- **Vehicle registration card:** parser, reader and tests exist in C# (`windows/SerbiaID.Windows/Cards.cs`, `VehicleCard.cs`; Windows, Windows XP / 7, Linux), Swift (`Sources/SerbiaID/VehicleCard.swift`; macOS, iOS) and Kotlin (`android/.../VehicleCard.kt`). They show on the first tab, renamed "Card": one Read button recognises an eID card first, then tries the registration application. Tested on synthetic data only. **Not checked on a real card.** The issuer signature is not verified. iOS reads it over a USB reader only (the NFC application list in Info.plist would need the confirmed application name).
- **Diagnostic mode** (`Diag.cs`, `CardDiag` in Swift and Kotlin): hidden in Settings (tap the version 5 times), `--diag [file]` on Windows and Linux. It selects the candidate applications and files, logs identifiers, sizes and status words and the structure (tags, lengths, kind of value) of what it can read, never a value, and sends no PIN command. A test checks that a planted value does not appear in the log.
- **Health insurance card:** nothing is implemented beyond the diagnostics. No official document describes the chip, and the sources do not show that its data is readable without a service card. It is added only after a real log shows that.
- **PDF / print:** the vehicle card has its own one-page A4 printout laid out after the printout of MUP's own reader "Čitač saobraćajne dozvole" (two sample printouts from that reader were supplied by the project owner: title, order of the fields, labels in Serbian Latin and positions are kept; an empty type or approval mark prints "-"; the typeface is the nearest available, Verdana first). The numbers are in `VehiclePrintSpec` (Cards.cs), `VehiclePrintLayout.swift` and `Pdf.kt` on Windows, Linux, macOS, iOS and Android, through the same Print / Save PDF buttons as the ID card. It carries the "not verified on a real card" note.
- **Not done:** signature check of the registration data (on purpose, see below); marketing text on the site (not added on purpose until a real card confirms the parser). The NFC path on iOS does not exist for this card and is not planned.
- **Why the signature is not checked:** the algorithm and hash of `E0xx` are not published in any source allowed here, and there is no real card to test against. A guessed check could report "invalid" for a genuine card or "valid" for nothing. The diagnostics already record whether `E0xx` and `C0xx` exist and their sizes; with that log the check can be written and tested.

## Differences between the task description and the repository
- A first look at an old checkout found no `docs/features.md`, changelog or `DiagLog`; they all exist on current `main` (this work is based on it). The log-copy button "Copy logs and errors" (`DiagLog`) is separate from the card diagnostics above.
- Languages: ru, en, sr (Latin and Cyrillic), hu, sq, sk, ro, hr, uk, be. The new texts are in `LocCards.cs` (all languages in one table), `LocalizationCards.swift` and the `strings.xml` files. The hu, sq, sk, ro, hr, uk and be texts were written without native speakers, like the existing ones.
- The release workflow needs a block `["X.Y.Z",` in `site/changelog/index.html`; the block for 1.6.0 is there. The changelog has a text for ru, en and sr only; the other languages show the English text (as for 1.5.0).
