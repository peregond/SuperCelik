<p align="center"><a href="README.md">English</a> · <a href="README.ru.md">Русский</a> · <b>Srpski</b></p>

# Super Čelik za Linux (beta)

Linux verzija je u **beta** statusu: to je označeno u prozoru aplikacije, a na kartici „O programu“ postoji veza ka [GitHub Issues](https://github.com/peregond/SuperCelik/issues/new) za prijavu grešaka i povratne informacije.

Avalonia (.NET 8). Protokol kartice, provera potpisa (CMS + lanac do MUP sertifikata), potpisivanje fajla i tekstovi zajednički su sa Windows verzijom:
fajlovi `windows/SerbiaID.Windows/{Card,CardErrors,Crypto,Models,Loc,SerbianScript,SelfTest}.cs` povezani su kao reference. Specifično za Linux:
pristup PC/SC-u preko `libpcsclite` (`Native.cs`), interfejs i raspored štampanog lista (`PrintSheet.cs`, PDF preko SkiaSharp-a).

## Šta je potrebno u sistemu
- `pcscd` i `libpcsclite1` (u .deb paketu su navedeni kao zavisnosti); na ne-Debian sistemima: `pcsc-lite` / `pcsclite`.
- USB čitač pametnih kartica. Ako aplikacija piše „Servis za pametne kartice nije pokrenut“: `sudo systemctl enable --now pcscd.socket`.
- `xdg-utils` za otvaranje PDF-a / stranice izdanja (nije obavezno).

## Čega nema u poređenju sa Windows-om
- Prijava u pregledaču sertifikatom sa kartice: na Linux-u se to radi PKCS#11 modulom (OpenSC ili [srb-id-pkcs11](https://github.com/ubavic/srb-id-pkcs11)) u podešavanjima pregledača; aplikacija to ne podešava. Dugme „Prijava na eUpravu“ na kartici „Token“ samo otvara stranicu za prijavu u podrazumevanom pregledaču.
- Štampa: „Štampaj“ čuva PDF u privremeni fajl i otvara ga u pregledaču (tamo je prozor za štampu), „Sačuvaj PDF“ stavlja fajl gde izaberete.

## Ažuriranja
Aplikacija proverava novu verziju i sama se ažurira. Sa `.deb` preuzima novi `.deb` i instalira ga preko `pkexec apt-get install` (sistem traži administratorsku lozinku); sa `.tar.gz` u folderu u koji može da piše preuzima **samo fajlove koji su se promenili** (izdanje ima `.manifest.json` sa SHA-256 svakog fajla i `.zip` iz kog aplikacija čita pojedinačne stavke HTTP zahtevima opsega; svaki fajl se proverava prema manifestu, a manifest prema kontrolnom zbiru GitHub-a) i zamenjuje ih na mestu, a pri neuspehu preuzima ceo `.tar.gz`. `.deb` se uvek instalira u celini, jer dpkg mora da zna fajlove. Paket se instalira samo ako se njegov SHA-256 poklapa sa kontrolnim zbirom koji GitHub prikazuje za fajl izdanja; u suprotnom aplikacija samo otvara stranicu izdanja. Posle ažuriranja aplikacija se ponovo pokreće.

## Pokretanje i provera
    dotnet run --project linux/SerbiaID.Linux -- --demo [kartica 0-3] [--dark] [--state noreader|nocard|busy|error]
    dotnet run --project linux/SerbiaID.Linux -- --demo --shot out.png      # prozor kao PNG (izmišljeni podaci)
    dotnet run --project linux/SerbiaID.Linux -- --demo --pdf out.pdf       # štampani list kao PDF
    SuperCelik --selftest                                                  # izveštaj o pravoj kartici bez ličnih podataka (selftest.txt pored programa, a ako je instalacioni folder samo za čitanje, u trenutnom folderu; putanja se može zadati: `--selftest report.txt`)

Podešavanja: `~/.config/SuperCelik/settings.json`. Jezik interfejsa se uzima iz `LANG` (ru / sr / en), menja se na kartici „Podešavanja“.

**Status:** nije probano na pravoj kartici pod Linux-om (razvoj je rađen na Mac-u: interfejs, PDF i gradnja su provereni, čitanje kartice preko `libpcsclite` i CMS potpis nisu provereni na Linux-u). Prvo pokrenite `--selftest`.
