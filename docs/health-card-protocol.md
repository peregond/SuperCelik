# Health insurance card (KZO, RFZO): how the official reader talks to the card

Status: **recovered by static analysis of the official software, NOT verified on a real card.**
Nothing here may be shown in the app as "verified" until a real-card diagnostic log
(`Settings → tap the version 5 times`, `--diag` on Windows/Linux) confirms it.

## Source and scope

- Source: the official RFZO program *РФЗО читач картица 3.0.0* ("КЗО Читач") and the NetSeT
  middleware it calls (*Web Client Services za zdravstvenu karticu* `nstwcs-hc-client` 1.3.4,
  COM component `nstwcsLib`). Installers were supplied by the project owner; they are **not**
  stored in this repository and no code was copied: only protocol facts needed for
  interoperability (command sequence, file ids, field layout) are written down here.
- No third-party open readers were looked at.
- The installers contain no licence text (no EULA dialog), so their terms of use were not
  checked; this is not legal advice.
- What the official program does **not** do: it asks for **no PIN**, and it never calls the
  `Verify*` functions, i.e. it does not check signatures. "Valid until" (`VerifiedUntil`) is
  not read from the card at all: the program fetches it online from an RFZO SOAP service.
  Our reader will not call that service (no public API description).

## Transport

Plain PC/SC (`SCardConnect`, `SCardTransmit`), T=0 or T=1, standard ISO 7816-4 APDUs.
The transport handles `61xx` (GET RESPONSE) and `6Cxx` (repeat with the right Le).
Every command below must answer `9000`, otherwise the official client raises
"Smart card applet return error code %04X".

## Identification step (`InitCard(reader, appId = 1)`)

The official app always passes `appId = 1`.

1. Try to select a card-manager application until one answers `9000`. Candidates, in this order
   (SELECT by name: `00 A4 04 00 Lc AID`):
   `A0000000030000`, `A000000003000000`, `A0000001510000`, `A000000018434D00`.
2. `80 CA 9F 7F` GET DATA (CPLC) → used to derive the chip serial number.
3. Select the card's own applet (`00 A4 04 00 Lc AID`):
   - card type 1: `F3 81 00 00 02 53 45 52 56 53 5A 4B 01` (13 bytes)
   - card type 7: `F3 81 00 00 02 53 45 52 53 4F 56 4F 5A 4B 01` (15 bytes)

   Only type 1 is used by the official reader (`appId = 1`).

The chip serial is later compared with the one written in the document block (tag `0x617`);
this is an anti-clone check that we do not need for plain reading.

## Reading one block (`ReadBlock(id)`), id ∈ { 0x0D01 … 0x0D04 }

1. `00 A4 04 00 0D F3 81 00 00 02 53 45 52 56 53 5A 4B 01`
   (select the card's own applet, the same AID as in the identification step; 13 bytes for
   type 1, 15 bytes for type 7). The card object keeps this AID in a member that the
   identification step fills in; the PKCS#15 AID `A000000063 PKCS-15` is only the default of the
   base class in the official library and is **not** used for these blocks.
2. `00 A4 00 00 02 <id hi> <id lo>` (select the elementary file by FID, FID = block id,
   big-endian in the command; the same form this project already uses for the token files).
   The response carries the file size: **bytes 2–3, big-endian**.
   The reader rejects a file smaller than 4 bytes.
3. `00 B0 00 00 04` READ BINARY, 4 bytes = block header.
4. READ BINARY from offset 0 in chunks of at most `0x80` (128) bytes
   (`00 B0 <offset hi> <offset lo> <len ≤ 80>`) until `4 + payload length` bytes are read.

Block layout, **all 16-bit fields little-endian**:

| Offset | Size | Meaning |
|---|---|---|
| 0 | 2 | block id (must equal the requested id, e.g. bytes `01 0D` for 0x0D01) |
| 2 | 2 | payload length (must not exceed the file size) |
| 4 | … | elements, back to back |

Element: `u16 tag (LE) | u16 length (LE) | value`. The parser scans the elements in order and
picks the one whose tag it needs; an element longer than the declared maximum is an error.
Some elements are optional (absent = "not set").

Value encodings (Windows code page ids in the official code):

- `ASCII` = code page 20127 (US-ASCII);
- `UTF-16LE` = code page 1200 (Cyrillic names, addresses, etc.);
- date = 8 ASCII characters `DDMMYYYY`;
- number = little-endian integer of the element's size (`Gender`: 1 = male, 2 = female
  per the official UI; `Permanent`: 0/1).

## Blocks and elements

Names are taken from the official COM interface and UI. The **tag ↔ name assignment is
inferred from declaration order and from field sizes** (sizes fit the meaning, e.g. ASCII 13 →
JMBG, ASCII 11 → LBO, ASCII 9 → PIB); it is strong but not proven. "max" is the declared
maximum length (bytes, from the official table).

### 0x0D01 Document (`ZKDocument`)

| Tag | Name | Type | max |
|---|---|---|---|
| 0x611 | InsurerName | UTF-16LE | 98 |
| 0x612 | InsurerID | ASCII | 15 |
| 0x613 | CardID | ASCII | 11 |
| 0x615 | DateOfIssue | date | 8 |
| 0x616 | DateOfExpiry | date | 8 |
| 0x617 | ChipSerialNumber | ASCII | 16 |
| 0x618 | PrintLanguage | ASCII | 2 |

### 0x0D02 Fixed personal (`ZKFixedPerso`)

| Tag | Name | Type | max |
|---|---|---|---|
| 0x621 | InsurantNumber (LBO) | ASCII | 11 |
| 0x622 | LastName | UTF-16LE | 100 |
| 0x623 | LastNameLatin | UTF-16LE | 100 |
| 0x624 | FirstName | UTF-16LE | 100 |
| 0x625 | FirstNameLatin | UTF-16LE | 100 |
| 0x626 | DateOfBirth | date | 8 |

(0x622–0x625 share identical attributes; their order is inferred from the interface.)

### 0x0D03 Variable personal (`ZKVariablePerso`: card validity)

| Tag | Name | Type | max |
|---|---|---|---|
| 0x630 | CardID | ASCII | 11 |
| 0x631 | DateOfIssue | date | 8 |
| 0x632 | DateOfExpiry (optional) | date | 8 |
| 0x633 | Permanent | number | 1 |

### 0x0D04 Variable administrative (`ZKVariableAdmin`)

| Tag | Name | Type | max |
|---|---|---|---|
| 0x640 | CardID | ASCII | 11 |
| 0x641 | ParentName | UTF-16LE | 100 |
| 0x642 | ParentNameLatin | UTF-16LE | 100 |
| 0x643 | Gender | number | 2 |
| 0x644 | IDNumber (JMBG) | ASCII | 13 |
| 0x645 | Street | UTF-16LE | 100 |
| 0x646 | PostNumber | ASCII | 5 |
| 0x647 | Municipality | UTF-16LE | 50 |
| 0x648 | Place | UTF-16LE | 50 |
| 0x649 | StreetCode | ASCII | 9 |
| 0x64A | Number | UTF-16LE | 10 |
| 0x64B | Entrance | UTF-16LE | 10 |
| 0x64C | Apartment | UTF-16LE | 10 |
| 0x64D | RZZOUserRegistrationNumber | ASCII | 10 |
| 0x64E | InsuranceBasisRZZOCode | ASCII | 4 |
| 0x64F | InsuranceBasisRZZO | UTF-16LE | 440 |
| 0x650 | CarrierRelationship | UTF-16LE | 40 |
| 0x651 | CarrierFamilyMember | number | (size not read by the analysis) |
| 0x652 | CarrierIdNumber | ASCII | 13 |
| 0x653 | CarrierInsurantNumber | ASCII | 11 |
| 0x654 | CarrierLastName | UTF-16LE | 100 |
| 0x655 | CarrierLastNameLatin | UTF-16LE | 100 |
| 0x656 | CarrierFirstName | UTF-16LE | 100 |
| 0x657 | CarrierFirstNameLatin | UTF-16LE | 100 |
| 0x658 | InsuredFrom | date | 8 |
| 0x659 | CountryCode | ASCII | 3 |
| 0x65A | Country | UTF-16LE | 100 |
| 0x65B | BookletIssuerCode | ASCII | 3 |
| 0x65C | InsurerBranch | UTF-16LE | 60 |
| 0x65D | InsurerOffice (optional) | UTF-16LE | 70 |
| 0x65E | TaxpayerName | UTF-16LE | 400 |
| 0x65F | TaxpayerResidence | UTF-16LE | 50 |
| 0x660 | TaxpayerNumber (PIB) | ASCII | 9 |
| 0x661 | TaxpayerIdNumber | ASCII | 13 |
| 0x662 | TaxpayerActivityCode | ASCII | 5 |
| 0x663 | ParticipationFreeBecause | ASCII | 3 |

Many of these are optional (the official COM objects expose `…Specified` flags for them).

## Other files the card has (not needed for reading)

Ids `0x0D00`, `0x0D05`, `0x0D06`, `0x0D07`, `0x0D09` exist in the official data model: they form
the integrity chain (a PKCS#7 "SOD" with SHA-256 hashes of the blocks, an RSA public key, and an
"active authentication" challenge/response using `00 22 41 B6` MSE + a random challenge).
Verification of these is **out of scope** for the first version: the official reader does not
do it either.

## Open questions only a real card can answer

- Does every card of this family answer the applet `SELECT` and the four FIDs without any
  access condition (the official program implies yes)?
- Exact element sizes/optionality, the `Gender`/`CarrierFamilyMember` number widths, and the
  tag-to-name assignment in blocks 0x0D02 and 0x0D04.
- Behaviour of cards of type 7 (second applet AID) and older cards without this applet.
