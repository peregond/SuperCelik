<p align="center"><img src="assets/icon-mac-1024.png" width="128" alt="Super Čelik"></p>

<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a> · <a href="README.sr.md">Srpski</a></p>

# Super Čelik

One app instead of Čelik + TrustEdge ID for the Serbian electronic ID card, foreigner ID card and residence permit. Free, no account, no servers: card data never leaves your device.
Website: <https://celik.peregon.cc> · What’s new: <https://celik.peregon.cc/changelog/> · Privacy policy: [docs/PRIVACY.md](docs/PRIVACY.md) · Bugs and feedback: [GitHub Issues](https://github.com/peregond/SuperCelik/issues/new)

Languages: RU / EN / SR (Latin) / SR (Cyrillic). Serbian Cyrillic is produced from Serbian Latin by automatic transliteration (`scripts/translit_sr.py`, the same rules in Swift and C#).
Platforms: **iOS and iPadOS** (SwiftUI, reads through a USB-C reader, see [ios/README.md](ios/README.md)), **macOS** (SwiftUI, see [macos/README.md](macos/README.md)), **Android** (Kotlin + Jetpack Compose, Material You, see [android/README.md](android/README.md)), **Windows** (WPF, .NET 8) and **Linux** (**beta**, Avalonia, .NET 8, see [linux/README.md](linux/README.md)).
An independent implementation, not affiliated with MUP RS or NetSeT/Veridos.

## Install
- **iPhone and iPad**: [App Store](https://apps.apple.com/app/id6835244146).
- **macOS 12+**: the same app in the [Mac App Store](https://apps.apple.com/app/id6835244146). To build without the store, see “Build from source”.
- **Android 8+**: `SuperCelik-<version>-android.apk` from [Releases](https://github.com/peregond/SuperCelik/releases) (to install it by hand, allow installation from unknown sources). Reads the card through a USB smart-card reader (USB-C or OTG): data, MUP signature check, token, PIN change, file signing, eUprava sign-in.
- **Windows 10/11 x64**: `SuperCelik-<version>-windows-x64-setup.exe`. The installer is not signed with a publisher certificate, so SmartScreen may warn you (“More info” → “Run anyway”).
- **Windows XP SP3 / Vista / 7 and 32-bit Windows**: `SuperCelik-<version>-windows-x86-legacy-setup.exe` (a separate build on .NET Framework 4.0, which the installer asks for if it is missing). Everything works the same except: browser-login driver needs Windows Vista or newer (not on XP), and automatic updates need TLS 1.2 (Windows 7 with updates; not on XP). Built in CI, not yet tried on a real XP.
- **Linux (x64 and arm64), beta**: `SuperCelik-<version>-linux-amd64.deb` / `-arm64.deb` (Debian, Ubuntu and derivatives: `sudo apt install ./SuperCelik-*.deb`, which pulls in `pcscd`) or `SuperCelik-<version>-linux-<x86_64|aarch64>.AppImage` (any distribution: `chmod +x` and run; needs `pcscd` and `libpcsclite1` on the system) or `SuperCelik-<version>-linux-<x86_64|aarch64>.flatpak` (`flatpak install --user ./SuperCelik-*.flatpak`; uses the host `pcscd` through `--socket=pcsc`, so it needs Flatpak 1.15.x or later; no browser sign-in module inside the sandbox) or `SuperCelik-<version>-linux-<x64|arm64>.tar.gz` (unpack and run `./SuperCelik`; needs `pcscd` and `libpcsclite1`). Reads the card through a USB reader over PC/SC; the .deb installs everything it needs (`pcscd`, the reader driver, the NSS tools) and all builds (except Flatpak) carry the browser sign-in module. It has not been tried on a real card under Linux yet: please report what you see in [Issues](https://github.com/peregond/SuperCelik/issues/new).

Builds are made automatically in GitHub Actions: every push to `main` → artifacts; a `vX.Y.Z` tag → a release.

## Build from source
macOS (Xcode 15+ / Swift 5.9):

    swift run                         # with a real reader
    SERBIAID_DEMO=1 swift run         # demo data, no card
    bash scripts/make-app.sh 0.9.9 arm64   # or x86_64 / universal → dist/*.dmg

Linux (.NET 8 SDK, `dpkg-deb` for the .deb):

    dotnet run --project linux/SerbiaID.Linux                      # with a real reader (needs pcscd)
    dotnet run --project linux/SerbiaID.Linux -- --demo            # demo data, no card
    bash scripts/make-linux.sh 0.9.9 x64                           # or arm64 → dist/*.deb, *.tar.gz, *.AppImage

Windows (.NET 8 SDK):

    dotnet build windows/SerbiaID.Windows -c Release
    windows\SerbiaID.Windows\bin\Release\net8.0-windows\SuperCelik.exe --selftest   # check on a real card, writes selftest.txt without personal data

## Status
- **Done on every platform:** interface in three languages, reader and ATR detection, reading personal data, address, document and photo, signature check (CMS + chain up to the MUP certificates from `Resources/CA`), reading the token certificate with chain validation, print / PDF.
- **Checked on a real card:** the Windows version (RP2024, `--selftest`): data, photo, both signatures and the token certificate chain. On macOS: PIN change, file signing and browser sign-in (see below). On iPhone: sign-in to eUprava through the system token (Safari) and the Home Screen quick actions.
- The protocol was obtained by observing `CelikApi.dll` and a real card; the fields were compared with the DLL's output. For the ID card (SERID) and the foreigner card (SERIF) the files are probably the same, but this is not verified; tags marked UNVERIFIED in the code are assumptions.
- **Token PIN:** “Change PIN”, “Unblock with PUK” and “Sign file” (detached CMS `.p7s`, SHA-256, token key 0x6005) are in the macOS, Windows, iOS and Android apps. **Not verified on a real token:** PIN change on Windows, iOS and Android, and **unblocking with PUK everywhere** (the APDU `00 2C 00 80` follows ISO 7816-4 and is not in public sources; a wrong PUK costs an attempt).
- **Browser sign-in with the card certificate (eid.gov.rs):** on **macOS** and **iOS** through the built-in card driver (CryptoTokenKit), verified on real cards. On **Android** the sign-in page opens inside the app with a card-backed key (checked in an emulator up to the signature call, not with a real card yet). On **Windows** the app registers its own card driver (one administrator prompt), and Chrome, Edge and Firefox take the certificate from the Windows store. On **Linux** the app connects the PKCS#11 module [srb-id-pkcs11](https://github.com/ubavic/srb-id-pkcs11) to Firefox, Chrome / Edge / Chromium ([linux/README.md](linux/README.md)). **Firefox** and **Edge** work on all three systems, see the sections below.
- **Linux is a beta:** built and tried in demo mode, not on a real card.
- Not done: the old Apollo card (protocol unknown).

## Sign-in on eid.gov.rs through Chrome / Edge / Safari (macOS)
Chrome, Edge and Safari on a Mac take client certificates only from the macOS keychain. The card gets there only through a system driver (CryptoTokenKit), and MUP / NetSeT have no driver for macOS, so the site used to say that no certificate was found even though Super Čelik read the card.

The driver is now inside the app (`SuperCelik.app/Contents/PlugIns/SuperCelikToken.appex`):
1. Install Super Čelik in Applications and run it once: it registers the driver and puts the MUP intermediate certificates into the “login” keychain (certificates only, trust is not changed).
2. Insert the card (if it was inserted before the installation, take it out and put it in again). To check in Terminal: `security list-smartcards` (a line `app.supercelik.token:SuperCelik-…` must appear) and `pluginkit -m -p com.apple.ctk-tokens`.
3. Quit Chrome or Edge completely (⌘Q, not just the window) and open the site again. This is required after every installation or update of the app and after inserting the card: if the browser visited the site while the card was not in the system, it remembers “no certificate” and shows no choice until it is restarted. The browser shows the certificate choice, and macOS asks for the PIN in a system window. A wrong PIN costs an attempt.

If the driver does not appear in `pluginkit -m -p com.apple.ctk-tokens`: `pluginkit -a /Applications/SuperCelik.app/Contents/PlugIns/SuperCelikToken.appex`, then take the card out and put it in. The driver log: `log show --last 10m --predicate 'subsystem == "app.supercelik.token"'`. Firefox: see the next section.

## Firefox
Firefox takes client certificates from the system on Windows and macOS, and from a PKCS#11 module on Linux:
- **Windows and macOS** (Firefox 90 and newer): from the system (the certificate store on Windows, the keychain on a Mac), where the card driver of Super Čelik puts the card certificate. There is nothing to install in Firefox: quit it completely and open the site again. If the preference `security.osclientcerts.autoload` is switched off in a profile (`about:config`), the app notices it and offers to turn it on (it adds one line to the `user.js` of that profile; the Mac App Store build cannot touch Firefox’s files, so there the switch in `about:config` is turned on by hand).
- **Linux:** there is no system store, so after you agree once the app connects its PKCS#11 module to every Firefox profile it finds: `~/.mozilla/firefox` and `~/.config/mozilla/firefox` (where Firefox 147 and newer keeps new profiles), and the profiles that `profiles.ini` lists elsewhere. A profile that appears later is connected automatically. Firefox from **Snap** (the default on Ubuntu) or **Flatpak** runs in a sandbox that keeps the module out (Ubuntu describes manual steps for Snap browsers, but calls them experimental), so the app leaves it alone: install Firefox as a regular package ([Mozilla’s instructions](https://support.mozilla.org/kb/install-firefox-linux)) or sign in with Chrome / Edge. Details and requirements: [linux/README.md](linux/README.md).

## Edge
Microsoft Edge is built on Chromium and signs in the same way as Chrome:
- **Windows and macOS:** from the system (the certificate store on Windows, the keychain on a Mac), where the card driver of Super Čelik puts the card certificate. There is nothing to install in Edge: quit it completely and open the site again.
- **Linux:** Edge shares one NSS database with Chrome, Chromium and Brave, so one registration serves all of them: after you agree once, the app connects its PKCS#11 module to it. The database is `~/.pki/nssdb`; Chromium 146 and newer (Edge follows it) use `~/.local/share/pki/nssdb` when the old one does not exist. The app connects the module to every copy that exists, and makes `~/.pki/nssdb` when there is none and one of these browsers is installed. Edge from Flatpak runs in a sandbox and is left alone, like Firefox from Snap. Details: [linux/README.md](linux/README.md).

## If the browser does not offer the card
Quit the browser completely (all windows; on a Mac ⌘Q) and open the sign-in page again. If that does not help, take the card out of the reader and put it back in. On **macOS** and **Linux** the “Check browser sign-in” button next to “Sign in to eUprava” shows what is wrong (reader and card, the card driver on a Mac or the module on Linux, Firefox) and says what to do next; on **Windows** the Settings tab shows the state of the driver and of Firefox.

## One version number
Every platform has the same version: the git tag `vX.Y.Z` of a release. The Windows, Linux, macOS and Android builds and the iOS test build take it from the tag, and the two App Store workflows (iOS and macOS) take the latest release tag by default, so the number in the stores is the number on GitHub. Every update gets a new tag. To release: put the changes of the release into a block of `site/changelog/index.html` named with the new number and date (a “Next release” block is renamed), merge it, then create the tag. The Android build number is computed from the version (1.3.2 gives 10302), the App Store build number is the workflow run number.

## Security
Do not commit card dumps or any personal data (see `.gitignore`).
