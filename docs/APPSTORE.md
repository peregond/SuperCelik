# Publishing to the App Store (iOS, iPadOS, macOS)

What is **already prepared** in the repository, and what **you** still have to do once you have the developer account.

## Prepared
| Item | Where |
|---|---|
| Privacy manifest (no tracking, no data collected, UserDefaults reason) | `ios/Config/PrivacyInfo.xcprivacy` (macOS: `macos/PrivacyInfo.xcprivacy`) |
| Export compliance (`ITSAppUsesNonExemptEncryption = false`), app category | `ios/Config/Info.plist` |
| Privacy policy (EN / RU / SR) | `docs/PRIVACY.md` |
| Store texts: name, subtitle, description, keywords, promo text, what's new (EN / RU / SR) | `appstore/metadata/<lang>/*.txt` (limits checked) |
| Notes for App Review + in-app demo data (Settings > Show demo data), so the reviewer needs no Serbian card | `appstore/REVIEW_NOTES.md` |
| iOS/iPadOS upload from CI (Apple's cloud signing, App Store Connect API key) | `.github/workflows/appstore-ios.yml`, `ios/ExportOptions.plist` |
| Mac App Store build (sandbox, no self-updater) | see `macos/` and the macOS section below |

## You need
1. **Apple Developer Program** membership (99 USD / year). It also gives the *NFC Tag Reading* capability the iOS app needs.
2. In **App Store Connect**: create the app records (iOS: bundle id `com.peregond.supercelik.ios`; macOS: `com.peregond.supercelik`).
   Change the ids in the Xcode project if they are taken. Fill in: privacy policy URL (a public link to `docs/PRIVACY.md` on GitHub works),
   support URL, category, age rating (no objectionable content), pricing, and paste `appstore/REVIEW_NOTES.md` into *App Review Information*.
3. **Screenshots** (required sizes): iPhone 6.9" (1320 x 2868), iPad 13" (2064 x 2752), Mac (at least 1280 x 800). The CI screenshot job
   (`Screenshots` workflow, demo data) produces iPhone/iPad images from the simulator; check the sizes and re-shoot at the exact sizes if needed.
4. **iOS / iPadOS**: add the repository secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` and run the
   *App Store (iOS / iPadOS)* workflow. The build appears in TestFlight; pick it in the app version and submit for review.
   Or open `ios/SuperCelik.xcodeproj` in Xcode, set your Team in *Signing & Capabilities*, then *Product > Archive > Distribute App*.
5. **macOS**: see below.

## macOS (Mac App Store)
The Mac App Store requires the app sandbox. The store build is the same code compiled with the `APPSTORE` flag:
no self-updater, no helper processes (`pluginkit`, `pkill`, `security`), smart card access through the
`com.apple.security.smartcard` entitlement. See `macos/README.md` for the certificates, provisioning profiles and secrets.

## Things that may block review (be ready)
- **Guideline 2.1 (App Completeness)**: the reviewer cannot test with a Serbian card, hence the demo data and the review notes. Keep them.
- **Guideline 5.2 (Intellectual property) / government-related apps**: this is an independent app for government ID cards and the name
  contains "Celik" (the official MUP app is "Čelik"). Apple may ask for proof of authorization or a rename. The description states that the app is
  independent. If asked, a different name (e.g. "Super eID Reader") avoids the question.
- **iPad has no NFC**: the app says so on iPad; reading there needs a USB reader, and whether iPadOS/iOS hand a CCID reader to the app is **not verified**.
- **Minimum functionality (4.2)**: the app has real functionality (reading, signature check, PDF, token, signing on Mac), but without a card the reviewer only
  sees the demo; make sure the review notes are filled in.
