<p align="center"><a href="README.md">English</a> · <a href="README.ru.md">Русский</a> · <b>Srpski</b></p>

# Super Čelik za Linux (beta)

Linux verzija je u **beta** statusu: to je označeno u prozoru aplikacije, a na kartici „O programu“ postoji veza ka [GitHub Issues](https://github.com/peregond/SuperCelik/issues/new) za prijavu grešaka i povratne informacije.

Avalonia (.NET 8). Protokol kartice, provera potpisa (CMS + lanac do MUP sertifikata), potpisivanje fajla i tekstovi zajednički su sa Windows verzijom:
fajlovi `windows/SerbiaID.Windows/{Card,CardErrors,Crypto,Models,Loc,SerbianScript,SelfTest}.cs` povezani su kao reference. Specifično za Linux:
pristup PC/SC-u preko `libpcsclite` (`Native.cs`), interfejs i raspored štampanog lista (`PrintSheet.cs`, PDF preko SkiaSharp-a).

## Šta je potrebno u sistemu
- **Sa `.deb` ništa ne treba ručno instalirati**: paket zavisi od `pcscd` (servis za pametne kartice), `libccid` (drajver USB čitača) i `libnss3-tools`, pa ih `apt` sam instalira, a posle instalacije pokreće servis (`pcscd.socket`). Ako aplikacija ipak piše „Servis za pametne kartice nije pokrenut“: `sudo systemctl enable --now pcscd.socket`.
- Sa **.tar.gz** (ili van Debian-a) sami instalirajte `pcscd`, `libpcsclite1` i `libccid` (na drugim sistemima `pcsc-lite`, `ccid`), kao i `libnss3-tools` ako želite podešavanje pregledača iz odeljka ispod.
- USB čitač pametnih kartica (CCID klase: gotovo svi).
- `xdg-utils` za otvaranje PDF-a / stranice izdanja (nije obavezno).

## Prijava u pregledaču (eUprava i drugi portali)
U gradnjama za x64, u folderu `pkcs11`, nalazi se PKCS#11 modul [srb-id-pkcs11](https://github.com/ubavic/srb-id-pkcs11) (javno dobro). Pri prvom pokretanju aplikacija nudi da ga poveže sa Firefox-om, Chrome-om, Edge-om i Chromium-om, a isto radi i dugme „Podesi prijavu u pregledaču“ na kartici „Token“ (pokreće `modutil` iz `libnss3-tools`; bez vaše saglasnosti ništa se ne menja). Posle toga potpuno zatvorite pregledač i ponovo ga otvorite.
- **Profili Firefox-a** traže se u `~/.mozilla/firefox` i u `$XDG_CONFIG_HOME/mozilla/firefox` (`~/.config/mozilla/firefox`: tamo Firefox 147 i noviji čuva nove profile), kao i svi profili koje `profiles.ini` navodi na drugim mestima.
- **Chrome, Chromium, Edge i Brave** dele jednu NSS bazu, pa jedna registracija služi svima. To je `~/.pki/nssdb`; Chromium 146 i noviji (Edge ga prati) koriste `~/.local/share/pki/nssdb` kad stare baze nema. Aplikacija povezuje modul sa svakom postojećom kopijom, a ako je nema i neki od ovih pregledača je instaliran, pravi `~/.pki/nssdb`, koju prihvataju sve verzije.
- Kad jednom pristanete, aplikacija sama ponovo povezuje modul (pri pokretanju i kad pritisnete „Prijava na eUpravu“) ako ga novi profil ili novi pregledač još nemaju, i javlja samo ono što je povezala.
- Modulu treba usluga za pametne kartice: dok je `pcscd` zaustavljen, NSS odbija da ga doda (`CKR_FUNCTION_FAILED`). Aplikacija to kaže: `sudo systemctl enable --now pcscd.socket`, pa ponovo pritisnite dugme.
- Modul se gradi iz autorovog izvornog koda u našem CI-ju za **glibc 2.28 ili noviji** (Ubuntu 20.04 i noviji, Debian 10 i noviji, Linux Mint 20 i noviji, RHEL 8 i noviji). Na starijem sistemu aplikacija kaže da NSS ne može da ga učita; tamo koristite OpenSC. Potrebna je i biblioteka `libpcsclite1`, instalira je .deb.
- Pregledači iz **Snap-a** ili **Flatpak-a** (Firefox i Chromium na Ubuntu-u; Chrome, Edge i Brave sa Flathub-a) rade u izolovanom okruženju koje ne propušta modul, pa ih aplikacija ne dira i to kaže. Ubuntu opisuje ručna podešavanja za Snap pregledače ([Enable smart cards in snapped browsers](https://documentation.ubuntu.com/desktop/en/latest/how-to/enable-smart-cards-in-snapped-browsers)), ali ih naziva eksperimentalnim; pouzdan put je običan paket: Firefox iz [Mozilla repozitorijuma](https://support.mozilla.org/kb/install-firefox-linux), Chrome ili Edge sa njihovih sajtova.
- Gradnje za **arm64** takođe sadrže modul (gradi se na isti način).

## Čega nema u poređenju sa Windows-om
- Štampa: „Štampaj“ čuva PDF u privremeni fajl i otvara ga u pregledaču (tamo je prozor za štampu), „Sačuvaj PDF“ stavlja fajl gde izaberete.

## Ažuriranja
Aplikacija proverava novu verziju i sama se ažurira. Sa `.deb` preuzima novi `.deb` i instalira ga preko `pkexec apt-get install` (sistem traži administratorsku lozinku); sa `.tar.gz` u folderu u koji može da piše preuzima **samo fajlove koji su se promenili** (izdanje ima `.manifest.json` sa SHA-256 svakog fajla i `.zip` iz kog aplikacija čita pojedinačne stavke HTTP zahtevima opsega; svaki fajl se proverava prema manifestu, a manifest prema kontrolnom zbiru GitHub-a) i zamenjuje ih na mestu, a pri neuspehu preuzima ceo `.tar.gz`. `.deb` se uvek instalira u celini, jer dpkg mora da zna fajlove. Paket se instalira samo ako se njegov SHA-256 poklapa sa kontrolnim zbirom koji GitHub prikazuje za fajl izdanja; u suprotnom aplikacija samo otvara stranicu izdanja. Posle ažuriranja aplikacija se ponovo pokreće.

## Pokretanje i provera
    dotnet run --project linux/SerbiaID.Linux -- --demo [kartica 0-3] [--dark] [--state noreader|nocard|busy|error]
    dotnet run --project linux/SerbiaID.Linux -- --demo --shot out.png      # prozor kao PNG (izmišljeni podaci)
    dotnet run --project linux/SerbiaID.Linux -- --demo --pdf out.pdf       # štampani list kao PDF
    SuperCelik --selftest                                                  # izveštaj o pravoj kartici bez ličnih podataka (selftest.txt pored programa, a ako je instalacioni folder samo za čitanje, u trenutnom folderu; putanja se može zadati: `--selftest report.txt`)

Podešavanja: `~/.config/SuperCelik/settings.json`. „Prikaži demo podatke“ na kartici „Podešavanja“ popunjava prozor izmišljenim podacima (kartica nije potrebna), a pri isključivanju vraća pravi čitač. Jezik interfejsa se uzima iz `LANG` (ru / sr / en), menja se na kartici „Podešavanja“.

**Status:** nije probano na pravoj kartici pod Linux-om (razvoj je rađen na Mac-u: interfejs, PDF i gradnja su provereni, čitanje kartice preko `libpcsclite` i CMS potpis nisu provereni na Linux-u). Prvo pokrenite `--selftest`.
