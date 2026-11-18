<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a> · <a href="README.sr.md">Srpski</a></p>

# Super Čelik for iPhone and iPad

The app reads the card through a wired smart-card reader (USB-C or MFi) and uses the same code as the Mac version:
the card protocol (`Sources/SerbiaID/EidCard.swift`), the MUP signature check, token certificate parsing
and the MUP print sheet (`MupPrintLayout.swift`, a PDF identical to the Mac one).
Available in the [App Store](https://apps.apple.com/app/id6835244146).

The app watches the reader: when a reader is connected and a card is inserted, it reads the card by itself (on the “Card” tab the personal data, on the “Token” tab the certificates). The “Card” and “Token” screens show whether a reader is connected and whether a card is inserted.

## Token: PIN, PUK, signing
The “Token” tab has “Change PIN” and “Unblock with PUK”. Both are **not verified on a real token** (the app says so in its own warning); a wrong PUK costs an attempt.

## Sign-in to eUprava with the card
The “Token” tab has “Sign in to eUprava”. iOS has no way for an app to hand a card key to Safari, so the app contains a **CryptoTokenKit token extension** (`ios/TokenExtension`, driver `SuperCelikTokenDriver`, class id `app.supercelik.token`): while the reader and the card are connected, iOS itself offers the card certificate to Safari and asks for the PIN in a system window. The app opens `https://euprava.gov.rs/prijava` in a full-screen Safari view. The extension needs the keychain group `$(AppIdentifierPrefix)com.apple.token`. The PIN window is drawn by iOS: its icon and keyboard are not controlled by the app. Verified on a real iPhone with a real card. If the driver is not attached (for example right after a reinstall), the app warns before opening the page.

## Home Screen quick actions
Long-press the app icon: “Read card”, “Print” and “Sign in to eUprava” (`QuickActions.swift`).

## NFC reading is disabled
The NFC reading code (`NFCCardReader.swift`) is still in the project but switched off with the flag `PhoneModel.nfcEnabled = false`.
The NFC permission was removed from `Config/SuperCelik.entitlements` and `Config/Info.plist`; how to bring it back is described in a comment
in the entitlements. According to public information the chip of Serbian ID cards is contact-only, so NFC does not suit them.

## Reader support on the device
A wired reader on an iPhone/iPad works only if iOS shows that reader to the app (`TKSmartCardSlotManager`). You need a USB-C iPhone 15 or newer or an iPad with a CCID reader, or an MFi reader.
If the system does not show the reader, the app stays in the “not connected” state.
Demo data (Settings → “Show demo data”) works without a card.

## Ready-made builds
For every PR and every release CI builds two files (in Actions: the artifact `SuperCelik-iOS`, in a release: next to the dmg):
- `SuperCelik-<version>-iOS-simulator.zip`: the app for the iPhone simulator on a Mac. Only Xcode is needed (it contains Simulator).
  Unpack it, start Simulator, pick any iPhone and drag `SuperCelik.app` onto the simulator window.
- `SuperCelik-<version>-iOS-unsigned.ipa`: a build for iPhone **without a signature**; you have to sign it with your own account
  (Sideloadly, AltStore, Apple Configurator or `Xcode → Devices`).

## Publishing to the App Store
See `docs/APPSTORE.md`: an app record with the bundle id `app.supercelik`, the secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` and the “App Store (iOS / iPadOS)” workflow.

## Build from Xcode
Open `ios/SuperCelik.xcodeproj` (download the whole repository: the project takes shared code from `Sources/SerbiaID`).
Target SuperCelik → Signing & Capabilities → choose your Team. If the bundle id `app.supercelik` is taken, change it.
