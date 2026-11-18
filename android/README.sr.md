<p align="center"><a href="README.md">English</a> · <a href="README.ru.md">Русский</a> · <b>Srpski</b></p>

# Super Čelik za Android

Kotlin + Jetpack Compose, Material You dizajn (dinamičke boje od Androida 12; na Androidu 8–11 paleta iz boja zastave).
Čita lične podatke i fotografiju srpske lične karte, lične karte za strance i boravišne dozvole **preko CCID USB čitača**
(na primer Gemalto CT40) povezanog USB-C ili OTG kablom: aplikacija sama razgovara sa čitačem preko USB host API-ja.

NFC čitanja nema: srpske lične karte imaju samo kontaktni čip (kao i u iOS verziji). NFC kod je uklonjen;
ako zatreba, nalazi se u git istoriji pre komita „Android: read only through a USB reader, drop NFC“.

Protokol kartice je prenet iz `Sources/SerbiaID/EidCard.swift`. Jezici: RU / EN / SR (prema jeziku sistema).

## Mogućnosti
- Čitanje ličnih podataka i fotografije (CCID USB čitač, automatski početak kada se čitač poveže), provera MUP potpisa po ugrađenim sertifikatima, rok važenja, PDF (deljenje).
- Kartica „Token“: sertifikati sa proverom lanca, izvoz `.cer`, promena PIN-a, otključavanje preko PUK-a, potpisivanje fajla (odvojeni CMS `.p7s`).
- Prijava na eUprava sertifikatom sa kartice (kartica „Token“, `EuLogin.kt`, `EuLoginActivity.kt`). Chrome na Androidu uzima
  klijentske sertifikate samo iz KeyChain-a, gde USB token ne dospeva. Zato se stranica za prijavu otvara u ugrađenom WebView-u, a na
  zahtev za sertifikat (`onReceivedClientCertRequest`) aplikacija odgovara sama. Ključ je referenca na karticu (`CardPrivateKey`),
  a TLS potpise pravi sopstveni JCA provajder: postavlja se prvi dok je ekran za prijavu otvoren i šalje potpis kartici preko USB-a.
  `prijavas.eid.gov.rs` radi samo preko TLS 1.2 i traži RSA PKCS#1 v1.5, pa popunjavanje (padding) radi kartica (MSE alg 2), a PSS nije potreban.
  PIN se traži u aplikaciji odmah pri izboru sertifikata i kartica ga odmah proverava, a ne tokom TLS rukovanja:
  rukovanje čeka potpis oko 30 sekundi, a sporo ukucan PIN je ranije završavao sa `ERR_TIMED_OUT`. Kartica ostaje
  uključena sa proverenim PIN-om do zahteva za potpis (do 90 s), posle potpisa još 15 s (za paralelne veze),
  zatim se isključuje. PIN se čuva samo u nizu znakova koji se briše posle jedinog VERIFY. Posle bilo kakvog
  neuspeha nema novih pokušaja dok korisnik ne pritisne „Počni ponovo“. Kolačići, skladište i keš WebView-a brišu se pri zatvaranju ekrana,
  a ako je aplikacija ubijena tokom prijave, pri sledećem pokretanju. Dozvola `INTERNET` potrebna je samo ovom ekranu;
  čitanje kartice ne koristi mrežu. Provereno na emulatoru do poziva potpisa (uključujući PIN unet 100 s posle zahteva). Sa pravom karticom još nije provereno.
- Privatnost: osetljiva polja su skrivena tačkama (oko ih prikazuje), automatsko brisanje podataka, ekran se ne pojavljuje na snimcima ekrana i u listi nedavnih aplikacija.
- Podešavanja: tema, dinamičke boje, maskiranje, automatsko brisanje, jezik (na Androidu 13+ u sistemskim podešavanjima aplikacije).

## Status
Gradi se u CI-ju i radi na emulatoru (demo podaci), ali **nije probano sa pravom karticom na telefonu i sa USB čitačem**. Kao i u verziji za Mac, otključavanje preko PUK-a nije provereno na kartici. Još nema: MUP štampanog lista (kao u verziji za Mac), samo jednostavan PDF.

## Gradnja
Android Studio (Narwhal ili novije) → otvorite folder `android` → Run. Ili iz komandne linije (potrebni su JDK 17, Android SDK 36 i Gradle 8.13+):

    gradle -p android assembleDebug

APK: `android/app/build/outputs/apk/debug/`. Gradi se i u GitHub Actions (artefakt `SuperCelik-android-debug`).

## Potpisivanje izdatih APK-ova
CI potpisuje izdati APK ključem iz tajni repozitorijuma: `ANDROID_KEYSTORE_BASE64` (.jks/.p12 fajl u base64),
`ANDROID_KEYSTORE_PASSWORD` i po želji `ANDROID_KEY_ALIAS` (podrazumevano `release`). Ako tajni nema, CI pravi jednokratni ključ:
APK se instalira, ali **ažuriranje preko prethodne gradnje neće proći** (drugi potpis). Napravite ključ jednom
(`keytool -genkeypair -keystore release.p12 -storetype PKCS12 -alias release -keyalg RSA -keysize 2048 -validity 10000`),
kodirajte `base64 -w0 release.p12` i dodajte u tajne. Sam ključ ne stavljajte u repozitorijum.
