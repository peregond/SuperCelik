<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a> · <a href="README.sr.md">Srpski</a></p>

# Super Čelik for Linux (beta)

The Linux version is a **beta**: the window says so, and the “About” tab has a link to [GitHub Issues](https://github.com/peregond/SuperCelik/issues/new) for bug reports and feedback.

Avalonia (.NET 8). The card protocol, signature check (CMS + chain up to the MUP certificates), file signing and texts are shared with the Windows version:
the files `windows/SerbiaID.Windows/{Card,CardErrors,Crypto,Models,Loc,SerbianScript,SelfTest}.cs` are linked in. What is specific to Linux:
PC/SC access through `libpcsclite` (`Native.cs`), the interface and the print sheet layout (`PrintSheet.cs`, PDF through SkiaSharp).

## What the system needs
- **With the .deb nothing has to be installed by hand**: the package depends on `pcscd` (smart-card service), `libccid` (driver of USB readers) and `libnss3-tools`, so `apt` installs them, and it starts the service (`pcscd.socket`) after the installation. If the app still says “The smart card service is not running”: `sudo systemctl enable --now pcscd.socket`.
- With the **.tar.gz** (or on non-Debian systems) install `pcscd`, `libpcsclite1` and `libccid` (`pcsc-lite`, `ccid` elsewhere) yourself, and `libnss3-tools` if you want the browser setup below.
- A USB smart-card reader (CCID class: nearly all of them).
- `xdg-utils` to open the PDF / the release page (optional).

## Browser sign-in (eUprava and other portals)
The x64 builds contain the PKCS#11 module [srb-id-pkcs11](https://github.com/ubavic/srb-id-pkcs11) (public domain) in the `pkcs11` folder. On the first start the app offers to connect it to Firefox and Chrome / Chromium, and the “Set up browser sign-in” button on the Token tab does the same at any time (it runs `modutil` from `libnss3-tools`; nothing is changed without your consent). Afterwards quit the browser completely and open it again. The **arm64** builds have no module (the author publishes no arm64 build): use OpenSC or build srb-id-pkcs11 yourself and add it to the browser by hand. Snap and Flatpak browsers are not configured automatically.

## Differences from Windows
- Updates: the app checks for a new version and updates itself. With the .deb it downloads the new .deb and installs it through `pkexec apt-get install` (the system asks for the administrator password); with the .tar.gz in a folder you can write to it downloads **only the files that changed** (the release has a `.manifest.json` with the SHA-256 of every file and a `.zip` that the app reads entry by entry with HTTP range requests; each file is checked against the manifest, and the manifest against GitHub's digest) and replaces them in place, falling back to the whole `.tar.gz` if that fails. A `.deb` is always installed whole, because dpkg has to know the files. The package is installed only if its SHA-256 equals the digest GitHub shows for the release file; otherwise the app just opens the release page. After updating, the app restarts.
- Printing: “Print” saves a PDF to a temporary file and opens it in the viewer (which has the print dialog); “Save PDF” puts the file where you choose.

## Run and check
    dotnet run --project linux/SerbiaID.Linux -- --demo [tab 0-3] [--dark] [--state noreader|nocard|busy|error]
    dotnet run --project linux/SerbiaID.Linux -- --demo --shot out.png      # the window as a PNG (fictional data)
    dotnet run --project linux/SerbiaID.Linux -- --demo --pdf out.pdf       # the print sheet as a PDF
    SuperCelik --selftest                                                  # a report on a real card without personal data (selftest.txt next to the program, or in the current folder if the install folder is read-only; a path can be given: `--selftest report.txt`)

Settings: `~/.config/SuperCelik/settings.json`. “Show demo data” on the Settings tab fills the window with fictional data (no card needed) and switches back to the real reader when turned off. The interface language comes from `LANG` (ru / sr / en) and can be changed on the “Settings” tab.

**Status:** not tried on a real card under Linux (development was done on a Mac: the interface, PDF and build were checked; card reading through `libpcsclite` and the CMS signature were not checked on Linux). Run `--selftest` first.
