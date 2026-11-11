import Foundation
import Security

/// Browser login with the eID / token certificate (e.g. registracijas.eid.gov.rs) on macOS.
///
/// Chrome and Safari on macOS take TLS client certificates only from the keychain. A smart card gets
/// there only through a CryptoTokenKit extension, which ships inside the app as
/// Contents/PlugIns/SuperCelikToken.appex. This makes sure macOS knows about it, and puts the bundled
/// MUP intermediate CA certificates into the login keychain (certificates only, no trust settings)
/// so the browser can match the card certificate to the CA list the site asks for.
enum BrowserLogin {
    static let extensionID = "com.peregond.supercelik.token"

    static func prepare() {
        DispatchQueue.global(qos: .utility).async {
            // After an update macOS can keep the OLD driver process alive and then refuses to start the new
            // one ("other version in use"): the card never shows up in the keychain and the browser finds
            // no certificate. Stopping the stale process once per app version avoids that; ctkd starts a
            // fresh one the next time a card is inserted.
            let key = "driverVersionSeen"
            let version = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
            if UserDefaults.standard.string(forKey: key) != version {
                stopRunningDriver()
                UserDefaults.standard.set(version, forKey: key)
                Thread.sleep(forTimeInterval: 1)
            }
            registerExtension()
            installIntermediates()
        }
    }

    /// LaunchServices normally registers app extensions on its own once the app is in /Applications;
    /// pluginkit makes it immediate and also re-enables the extension if it was turned off.
    private static func registerExtension() {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return }
        let appex = plugins.appendingPathComponent("SuperCelikToken.appex")
        guard FileManager.default.fileExists(atPath: appex.path) else { return }
        run("/usr/bin/pluginkit", ["-a", appex.path])
        run("/usr/bin/pluginkit", ["-e", "use", "-i", extensionID])
    }

    private static func installIntermediates() {
        for cert in SignatureVerifier.anchors {
            // Roots are skipped: adding them would not make them trusted anyway, and trust is the
            // user's call. Intermediates only help path building.
            let subject = SecCertificateCopyNormalizedSubjectSequence(cert) as Data?
            let issuer = SecCertificateCopyNormalizedIssuerSequence(cert) as Data?
            guard subject != nil, subject != issuer else { continue }
            let status = SecItemAdd([kSecClass as String: kSecClassCertificate,
                                     kSecValueRef as String: cert] as CFDictionary, nil)
            if status != errSecSuccess && status != errSecDuplicateItem {
                NSLog("SuperCelik: could not add CA certificate to keychain: \(status)")
            }
        }
    }

    /// Stops a running driver process (it belongs to the user; ctkd relaunches it on demand).
    static func stopRunningDriver() {
        run("/usr/bin/pkill", ["-f", "SuperCelikToken.appex"])
    }

    /// True when macOS lists our token among its smart cards, i.e. the driver is attached to the card.
    static func driverAttached() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["list-smartcards"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return true }      // cannot check -> do not nag
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: out, encoding: .utf8)?.contains(extensionID) ?? true
    }

    /// Re-registers the driver and stops a stale instance. Returns after the system had time to settle.
    static func repairDriver() {
        stopRunningDriver()
        Thread.sleep(forTimeInterval: 1)
        registerExtension()
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
