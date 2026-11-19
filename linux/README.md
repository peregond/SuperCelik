<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a> · <a href="README.sr.md">Srpski</a></p>

# Super Čelik for Linux (beta)

The Linux version is a **beta**: the window says so, and the “About” tab has a link to [GitHub Issues](https://github.com/peregond/SuperCelik/issues/new) for bug reports and feedback.

Avalonia (.NET 8). The card protocol, signature check (CMS + chain up to the MUP certificates), file signing and texts are shared with the Windows version:
the files `windows/SerbiaID.Windows/{Card,CardErrors,Crypto,Models,Loc,SerbianScript,SelfTest}.cs` are linked in. What is specific to Linux:
PC/SC access through `libpcsclite` (`Native.cs`), the interface and the print sheet layout (`PrintSheet.cs`, PDF through SkiaSharp).

## What the system needs
- `pcscd` and `libpcsclite1` (the .deb declares them as dependencies); on non-Debian systems: `pcsc-lite` / `pcsclite`.
- A USB smart-card reader. If the app says “The smart card service is not running”: `sudo systemctl enable --now pcscd.socket`.
- `xdg-utils` to open the PDF / the release page (optional).

## What is missing compared with Windows
- Browser sign-in with the card certificate: on Linux this is done with a PKCS#11 module (OpenSC or [srb-id-pkcs11](https://github.com/ubavic/srb-id-pkcs11)) in the browser settings; the app does not configure it. The “Sign in to eUprava” button on the Token tab only opens the sign-in page in your default browser.
- Updates: the app checks for a new version and updates itself. With the .deb it downloads the new .deb and installs it through `pkexec apt-get install` (the system asks for the administrator password); with the .tar.gz in a folder you can write to it downloads **only the files that changed** (the release has a `.manifest.json` with the SHA-256 of every file and a `.zip` that the app reads entry by entry with HTTP range requests; each file is checked against the manifest, and the manifest against GitHub's digest) and replaces them in place, falling back to the whole `.tar.gz` if that fails. A `.deb` is always installed whole, because dpkg has to know the files. The package is installed only if its SHA-256 equals the digest GitHub shows for the release file; otherwise the app just opens the release page. After updating, the app restarts.
- Printing: “Print” saves a PDF to a temporary file and opens it in the viewer (which has the print dialog); “Save PDF” puts the file where you choose.

## Run and check
    dotnet run --project linux/SerbiaID.Linux -- --demo [tab 0-3] [--dark] [--state noreader|nocard|busy|error]
    dotnet run --project linux/SerbiaID.Linux -- --demo --shot out.png      # the window as a PNG (fictional data)
    dotnet run --project linux/SerbiaID.Linux -- --demo --pdf out.pdf       # the print sheet as a PDF
    SuperCelik --selftest                                                  # a report on a real card without personal data (selftest.txt next to the program, or in the current folder if the install folder is read-only; a path can be given: `--selftest report.txt`)

Settings: `~/.config/SuperCelik/settings.json`. The interface language comes from `LANG` (ru / sr / en) and can be changed on the “Settings” tab.

**Status:** not tried on a real card under Linux (development was done on a Mac: the interface, PDF and build were checked; card reading through `libpcsclite` and the CMS signature were not checked on Linux). Run `--selftest` first.
