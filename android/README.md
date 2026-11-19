<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a> · <a href="README.sr.md">Srpski</a></p>

# Super Čelik for Android

Kotlin + Jetpack Compose, Material You design (dynamic colors from Android 12; on Android 8–11 a palette from the flag colors).
Reads the personal data and photo of a Serbian ID card, foreigner ID card and residence permit **through a CCID USB reader**
(for example Gemalto CT40) connected with a USB-C or OTG cable: the app talks to the reader itself through the USB host API.

There is no NFC reading: Serbian ID cards have a contact-only chip (just as in the iOS version). The NFC code was removed;
if you need it back, it is in git history before the commit “Android: read only through a USB reader, drop NFC”.

The card protocol is ported from `Sources/SerbiaID/EidCard.swift`. Languages: RU / EN / SR (by the system language).

## Features
- Reading personal data and photo (CCID USB reader, starts automatically when a reader is connected), MUP signature check against built-in certificates, expiry date, PDF (share).
- “Token” tab: certificates with chain validation, `.cer` export, PIN change, unblock with PUK, file signing (detached CMS `.p7s`).
- Sign-in to eUprava with the card certificate (“Token” tab, `EuLogin.kt`, `EuLoginActivity.kt`). Chrome on Android takes
  client certificates only from KeyChain, where a USB token does not get. So the sign-in page opens in an in-app WebView, and the app answers
  the certificate request (`onReceivedClientCertRequest`) itself. The key is a reference to the card (`CardPrivateKey`),
  and TLS signatures are made by our own JCA provider: it is installed first while the sign-in screen is open and sends the signature to the card over USB.
  `prijavas.eid.gov.rs` works only over TLS 1.2 and asks for RSA PKCS#1 v1.5, so the card does the padding (MSE alg 2) and PSS is not needed.
  The PIN is asked in the app right when the certificate is chosen and the card checks it at once, not during the TLS handshake:
  the handshake waits for the signature for about 30 seconds, and a slowly typed PIN used to end in `ERR_TIMED_OUT`. The card stays
  switched on with the verified PIN until the signature request (up to 90 s), 15 s more after the signature (for parallel connections),
  then it is switched off. The PIN is kept only in a character array that is wiped after the single VERIFY. After any
  failure there are no new attempts until the user taps “Start over”. The cookies, storage and cache of the WebView are erased when the screen closes,
  or, if the app was killed during sign-in, at the next start. The `INTERNET` permission is needed only by this screen;
  card reading does not use the network. Checked in an emulator up to the signature call (including a PIN entered 100 s after the request). Not yet checked with a real card.
- Privacy: sensitive fields are hidden with dots (the eye shows them), automatic data clearing, the screen is excluded from screenshots and the recent apps list.
- Settings: theme, dynamic colors, masking, auto-clear, language (on Android 13+ in the system settings of the app).

## Status
Builds in CI and runs in an emulator (demo data), but **has not been tried with a real card on a phone and with a USB reader**. As in the Mac version, unblocking with PUK is not verified on a card. Not there yet: the MUP print sheet (as in the Mac version), only a simple PDF.

## Build
Android Studio (Narwhal or newer) → open the `android` folder → Run. Or on the command line (needs JDK 17, Android SDK 36 and Gradle 8.13+):

    gradle -p android assembleDebug

The APK: `android/app/build/outputs/apk/debug/`. It is also built in GitHub Actions (artifact `SuperCelik-android-debug`).

## Signing release APKs
CI signs the release APK with a key from the repository secrets: `ANDROID_KEYSTORE_BASE64` (a .jks/.p12 file in base64),
`ANDROID_KEYSTORE_PASSWORD` and optionally `ANDROID_KEY_ALIAS` (default `release`). Without secrets CI creates a one-time key:
the APK installs, but **an update over a previous build will not install** (a different signature). Create a key once
(`keytool -genkeypair -keystore release.p12 -storetype PKCS12 -alias release -keyalg RSA -keysize 2048 -validity 10000`),
encode it with `base64 -w0 release.p12` and add it to the secrets. Do not put the key itself into the repository.
