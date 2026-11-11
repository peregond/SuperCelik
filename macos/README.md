# Mac App Store build

The store build is the same source as the direct-download app, compiled with `-Xswiftc -DAPPSTORE`:
- no self-updater (Mac App Store apps must not update themselves) and no network code;
- no helper processes (`pluginkit`, `pkill`, `security`): in the sandbox macOS finds and starts the bundled
  CryptoTokenKit extension itself;
- sandbox + `com.apple.security.smartcard` (PC/SC), user-selected file access, printing (`AppStore.entitlements`);
- the extension is sandboxed too (`AppStoreToken.entitlements`).

Build (on a Mac): `bash scripts/make-appstore-mac.sh <version> <build>`.
`UNSIGNED=1` makes an ad-hoc signed app for a layout check (CI does this). A store package needs, from your developer account:

| What | Where to get it |
|---|---|
| Team id (`TEAM_ID`) | developer.apple.com > Membership |
| *3rd Party Mac Developer Application* (or *Apple Distribution*) certificate | Certificates, Identifiers & Profiles |
| *3rd Party Mac Developer Installer* certificate | same |
| App IDs `com.peregond.supercelik` and `com.peregond.supercelik.token` (Mac) | Identifiers |
| Two *Mac App Store* provisioning profiles, one per App ID | Profiles |
| App Store Connect API key (to upload) | App Store Connect > Users and Access > Integrations |

The `App Store (macOS)` workflow does all of it from repository secrets; see its header.

**Not verified:** nothing here could be signed or run in the sandbox without a developer account. Likely first-round findings:
the sandbox profile for the CryptoTokenKit extension, and Safari/Chrome keychain visibility of the card in the sandboxed build.
