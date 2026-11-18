<p align="center"><a href="README.md">English</a> · <a href="README.ru.md">Русский</a> · <b>Srpski</b></p>

# Gradnja za Mac App Store

Prodavnička gradnja pravi se iz istog koda kao aplikacija za direktno preuzimanje i kompajlira se sa `-Xswiftc -DAPPSTORE`:
- bez samoažuriranja (aplikacije Mac App Store-a ne smeju same da se ažuriraju) i bez mrežnog koda;
- bez pomoćnih procesa (`pluginkit`, `pkill`, `security`): u peščaniku (sandbox) macOS sam pronalazi i pokreće
  ugrađeno CryptoTokenKit proširenje;
- peščanik + `com.apple.security.smartcard` (PC/SC), pristup fajlovima koje korisnik izabere, štampa (`AppStore.entitlements`);
- proširenje takođe radi u peščaniku (`AppStoreToken.entitlements`).

Gradnja (na Mac-u): `bash scripts/make-appstore-mac.sh <verzija> <gradnja>`.
`UNSIGNED=1` pravi aplikaciju sa ad-hoc potpisom za proveru sastava (to radi CI). Za paket prodavnice potrebno je iz razvojnog naloga:

| Šta | Gde se dobija |
|---|---|
| Team id (`TEAM_ID`) | developer.apple.com > Membership |
| Sertifikat *3rd Party Mac Developer Application* (ili *Apple Distribution*) | Certificates, Identifiers & Profiles |
| Sertifikat *3rd Party Mac Developer Installer* | isto |
| App ID-jevi `app.supercelik` i `app.supercelik.token` (Mac) | Identifiers |
| Dva profila *Mac App Store*, po jedan za svaki App ID | Profiles |
| Ključ App Store Connect API (za otpremanje) | App Store Connect > Users and Access > Integrations |

Workflow `App Store (macOS)` sve to radi iz tajni repozitorijuma; vidi njegovo zaglavlje.

**Nije provereno:** bez razvojnog naloga ovde se ništa nije moglo potpisati niti pokrenuti u peščaniku. Verovatne primedbe prvog kruga:
profil peščanika za CryptoTokenKit proširenje i vidljivost kartice u Safari/Chrome keychain-u u gradnji sa peščanikom.
