<p align="center"><a href="README.md">English</a> · <a href="README.ru.md">Русский</a> · <b>Srpski</b></p>

# Super Čelik za iPhone i iPad

Aplikacija čita karticu preko žičanog čitača pametnih kartica (USB-C ili MFi) i koristi isti kod kao verzija za Mac:
protokol kartice (`Sources/SerbiaID/EidCard.swift`), proveru MUP potpisa, obradu sertifikata
tokena i MUP štampani list (`MupPrintLayout.swift`, PDF identičan onom na Mac-u).
Dostupno u [App Store](https://apps.apple.com/app/id6835244146).

Aplikacija prati čitač: kada je čitač povezan i kartica ubačena, sama počinje čitanje (na kartici „Kartica“ lične podatke, na kartici „Token“ sertifikate). Ekrani „Kartica“ i „Token“ pokazuju da li je čitač povezan i da li je kartica ubačena.

## Token: PIN, PUK, potpis
Na kartici „Token“ postoje „Promeni PIN“ i „Otključaj preko PUK-a“. Obe funkcije **nisu proverene na pravom tokenu** (aplikacija to kaže u svom upozorenju); pogrešan PUK troši pokušaj.

## Prijava na eUprava karticom
Na kartici „Token“ postoji „Prijavi se na eUprava“. U iOS-u aplikacija ne može da prosledi ključ kartice Safari-ju, zato unutra postoji **proširenje-token CryptoTokenKit** (`ios/TokenExtension`, drajver `SuperCelikTokenDriver`, class id `app.supercelik.token`): dok su čitač i kartica povezani, sam iOS nudi Safari-ju sertifikat kartice i traži PIN u sistemskom prozoru. Aplikacija otvara `https://euprava.gov.rs/prijava` u Safari prozoru preko celog ekrana. Proširenju je potrebna grupa lanca ključeva `$(AppIdentifierPrefix)com.apple.token`. Prozor za PIN crta iOS: ikonu i tastaturu u njemu aplikacija ne kontroliše. Provereno na pravom iPhone-u sa pravom karticom. Ako drajver nije povezan (na primer odmah posle ponovne instalacije), aplikacija upozorava pre otvaranja stranice.

## Brze radnje na početnom ekranu
Dugi pritisak na ikonu: „Pročitaj karticu“, „Štampaj“ i „Prijavi se na eUprava“ (`QuickActions.swift`).

## Čitanje preko NFC-a je isključeno
Kod za čitanje preko NFC-a (`NFCCardReader.swift`) je ostao u projektu, ali je isključen zastavicom `PhoneModel.nfcEnabled = false`.
Dozvola za NFC je uklonjena iz `Config/SuperCelik.entitlements` i `Config/Info.plist`; kako se vraća, piše u komentaru
u entitlements fajlu. Prema javnim podacima čip srpskih ličnih karata je samo kontaktni, pa NFC za njih ne odgovara.

## Podrška za čitače na uređaju
Žičani čitač na iPhone-u/iPad-u radi samo ako iOS prikazuje taj čitač aplikaciji (`TKSmartCardSlotManager`). Potreban je USB-C iPhone 15 ili noviji, ili iPad sa CCID čitačem, ili MFi čitač.
Ako sistem ne prikazuje čitač, aplikacija ostaje u stanju „nije povezan“.
Demo podaci (Podešavanja → „Prikaži demo podatke“) rade bez kartice.

## Gotove gradnje
CI za svaki PR i za svako izdanje gradi dva fajla (u Actions: artefakt `SuperCelik-iOS`, u izdanju: pored dmg-a):
- `SuperCelik-<verzija>-iOS-simulator.zip`: aplikacija za iPhone simulator na Mac-u. Potreban je samo Xcode (u njemu je Simulator).
  Raspakujte, pokrenite Simulator, izaberite bilo koji iPhone i prevucite `SuperCelik.app` na prozor simulatora.
- `SuperCelik-<verzija>-iOS-unsigned.ipa`: gradnja za iPhone **bez potpisa**; treba je potpisati svojim nalogom
  (Sideloadly, AltStore, Apple Configurator ili `Xcode → Devices`).

## Objavljivanje u App Store
Vidi `docs/APPSTORE.md`: zapis aplikacije sa bundle id-jem `app.supercelik`, tajne `APPLE_TEAM_ID`, `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` i workflow „App Store (iOS / iPadOS)“.

## Gradnja iz Xcode-a
Otvorite `ios/SuperCelik.xcodeproj` (repozitorijum treba preuzeti u celini: projekat uzima zajednički kod iz `Sources/SerbiaID`).
Cilj SuperCelik → Signing & Capabilities → izaberite svoj tim (Team). Ako je bundle id `app.supercelik` zauzet, promenite ga.
