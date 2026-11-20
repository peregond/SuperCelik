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
U gradnjama za x64, u folderu `pkcs11`, nalazi se PKCS#11 modul [srb-id-pkcs11](https://github.com/ubavic/srb-id-pkcs11) (javno dobro). Pri prvom pokretanju aplikacija nudi da ga poveže sa Firefox-om i Chrome-om / Chromium-om, a isto radi i dugme „Podesi prijavu u pregledaču“ na kartici „Token“ (pokreće `modutil` iz `libnss3-tools`; bez vaše saglasnosti ništa se ne menja). Posle toga potpuno zatvorite pregledač i ponovo ga otvorite.
- **Profili Firefox-a** traže se u `~/.mozilla/firefox` i u `$XDG_CONFIG_HOME/mozilla/firefox` (`~/.config/mozilla/firefox`: tamo Firefox 147 i noviji čuva nove profile), kao i svi profili koje `profiles.ini` navodi na drugim mestima. Kad jednom pristanete, aplikacija sama ponovo povezuje modul (pri pokretanju i kad pritisnete „Prijava na eUpravu“) ako ga novi profil ili novi pregledač još nemaju, i javlja samo ono što je povezala.
- Modulu treba usluga za pametne kartice: dok je `pcscd` zaustavljen, NSS odbija da ga doda (`CKR_FUNCTION_FAILED`). Aplikacija to kaže: `sudo systemctl enable --now pcscd.socket`, pa ponovo pritisnite dugme.
- Firefox iz **Snap-a** (podrazumevan na Ubuntu-u) ili **Flatpak-a** radi u izolovanom okruženju koje ne može da učita modul spolja, pa ga aplikacija ne dira i to kaže: instalirajte Firefox kao običan paket ([Mozilline instrukcije](https://support.mozilla.org/kb/install-firefox-linux)) ili koristite Chrome / Chromium.
- Gradnje za **arm64** nemaju modul (autor ne objavljuje arm64 gradnju): povežite OpenSC ili sami izgradite srb-id-pkcs11 i dodajte ga u pregledač ručno.

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
