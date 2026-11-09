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
