<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a> · <a href="README.sr.md">Srpski</a></p>

# Super Čelik for Linux (beta)

The Linux version is a **beta**: the window says so, and the “About” tab has a link to [GitHub Issues](https://github.com/peregond/SuperCelik/issues/new) for bug reports and feedback.

Avalonia (.NET 8). The card protocol, signature check (CMS + chain up to the MUP certificates), file signing and texts are shared with the Windows version:
the files `windows/SerbiaID.Windows/{Card,CardErrors,Crypto,Models,Loc,SerbianScript,SelfTest}.cs` are linked in. What is specific to Linux:
PC/SC access through `libpcsclite` (`Native.cs`), the interface and the print sheet layout (`PrintSheet.cs`, PDF through SkiaSharp).

## What the system needs
- **With the .deb nothing has to be installed by hand**: the package depends on `pcscd` (smart-card service), `libccid` (driver of USB readers) and `libnss3-tools`, so `apt` installs them, and it starts the service (`pcscd.socket`) after the installation. If the app still says “The smart card service is not running”: `sudo systemctl enable --now pcscd.socket`.
- With the **.tar.gz** (or on non-Debian systems) install `pcscd`, `libpcsclite1` and `libccid` (`pcsc-lite`, `ccid` elsewhere) yourself, and `libnss3-tools` if you want the browser setup below.
- The **.AppImage** (any distribution): `chmod +x SuperCelik-*.AppImage && ./SuperCelik-*.AppImage`. It needs the same system parts as the .tar.gz (`pcscd`, `libpcsclite1`, `libccid`). It updates itself by replacing the file (checked against the SHA-256 of the release); the browser module is copied to `~/.local/share/SuperCelik/pkcs11` before it is added to a browser, because the AppImage is mounted at a new path on each start.
- The **Flatpak** bundle: `flatpak install --user ./SuperCelik-*.flatpak`. The sandbox has no card service of its own: it talks to the host's `pcscd` through `--socket=pcsc` (Flatpak 1.15.x or later; the host needs `pcscd` and `libccid`). The browser sign-in module is not included (a host browser cannot load a library from inside the sandbox) and the app does not update itself: use `flatpak update`. Built by `scripts/make-linux-flatpak.sh` from the same files as the other packages (manifest in `linux/packaging/flatpak`); not on Flathub yet.
- A USB smart-card reader (CCID class: nearly all of them).
- `xdg-utils` to open the PDF / the release page (optional).

## Browser sign-in (eUprava and other portals)
The x64 builds contain the PKCS#11 module [srb-id-pkcs11](https://github.com/ubavic/srb-id-pkcs11) (public domain) in the `pkcs11` folder. On the first start the app offers to connect it to Firefox, Chrome, Edge and Chromium, and the “Set up browser sign-in” button on the Token tab does the same at any time (it runs `modutil` from `libnss3-tools`; nothing is changed without your consent). Afterwards quit the browser completely and open it again.
- **Firefox profiles** are looked for in `~/.mozilla/firefox` and in `$XDG_CONFIG_HOME/mozilla/firefox` (`~/.config/mozilla/firefox`, where Firefox 147 and newer keeps new profiles), plus every profile that `profiles.ini` lists elsewhere.
- **Chrome, Chromium, Edge and Brave** share one NSS database, so one registration serves all of them. It is `~/.pki/nssdb`; Chromium 146 and newer (Edge follows it) use `~/.local/share/pki/nssdb` when the old one does not exist. The app connects the module to every copy that exists, and when there is none and one of these browsers is installed, it makes `~/.pki/nssdb`, which every version picks up.
- Once you have agreed, the app connects the module again by itself (when it starts, and when you press “Sign in to eUprava”) if a new profile or a newly installed browser does not have it yet, and tells you only when it did.
- The module needs the smart card service: while `pcscd` is stopped NSS refuses to add it (`CKR_FUNCTION_FAILED`). The app says so: `sudo systemctl enable --now pcscd.socket`, then press the button again.
- The module is built from the author’s source in our CI for **glibc 2.28 or newer** (Ubuntu 20.04 and newer, Debian 10 and newer, Linux Mint 20 and newer, RHEL 8 and newer). On an older system the app says that NSS cannot load it; use OpenSC there. It also needs `libpcsclite1`, which the .deb installs.
- Browsers from **Snap** or **Flatpak** (Firefox and Chromium on Ubuntu; Chrome, Edge and Brave from Flathub) run in a sandbox that keeps the module out, so the app leaves them alone and says so. Ubuntu describes manual steps for Snap browsers ([Enable smart cards in snapped browsers](https://documentation.ubuntu.com/desktop/en/latest/how-to/enable-smart-cards-in-snapped-browsers)) but calls them experimental; the reliable way is a regular package: Firefox from [Mozilla’s repository](https://support.mozilla.org/kb/install-firefox-linux), Chrome or Edge from their websites.
- The **arm64** builds include the module too (built the same way).

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
