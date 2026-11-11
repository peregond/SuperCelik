import Foundation
import Security
import CryptoKit

enum SignatureVerifier {
    /// SHA-256 of `data`, wrapped so callers can ask `isSubset(of:)` against a signed hash list.
    struct Digest {
        let value: Data
        func isSubset(of content: Data) -> Bool {
            var i = 0
            while i + 32 <= content.count {
                if content[(content.startIndex + i)..<(content.startIndex + i + 32)] == value { return true }
                i += 32
            }
            return false
        }
    }

    static func sha256(_ data: Data) -> Digest { Digest(value: Data(SHA256.hash(data: data))) }

    /// MUP root + intermediate CAs shipped inside the app bundle.
    static let anchors: [SecCertificate] = {
        let urls = resourceBundle?.urls(forResourcesWithExtension: "crt", subdirectory: "Resources/CA")
            ?? Bundle.main.urls(forResourcesWithExtension: "crt", subdirectory: "CA")   // iOS app (ios/SuperCelik.xcodeproj)
            ?? []
        return urls.compactMap { url in
            (try? Data(contentsOf: url)).flatMap(derFromFile).flatMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        }
    }()

    /// The .crt files are a mix of DER (MUPCA 3) and PEM (MUP CA 4); SecCertificate only takes DER.
    /// Silently dropping the PEM ones left the whole CA 4 hierarchy out, so current token and card
    /// certificates failed with "could not build the trust chain".
    static func derFromFile(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .ascii), text.contains("-----BEGIN CERTIFICATE-----") else {
            return data
        }
        let b64 = text.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        return Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
    }

    /// The SwiftPM resource bundle with the CA certificates.
    /// `Bundle.module` is not used on purpose: it only looks next to the .app (not in
    /// Contents/Resources, where make-app.sh puts it) and traps when the bundle is missing,
    /// which crashed the app on "Read token". Here a missing bundle just means no anchors,
    /// so the chain check reports "not trusted" instead of crashing.
    private static let resourceBundle: Bundle? = {
        let name = "SerbiaID_SerbiaID.bundle"
        var dirs: [URL?] = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                            Bundle.main.executableURL?.deletingLastPathComponent()]
        dirs.append(Bundle(for: BundleFinder.self).resourceURL)
        for case let dir? in dirs {
            if let b = Bundle(url: dir.appendingPathComponent(name)) { return b }
        }
        return nil
    }()
    private final class BundleFinder {}

    /// Verifies a BER CMS SignedData: signature, signer certificate chain (MUP CAs only).
    /// Returns the signed content.
    static func verifyCMS(_ blob: Data) throws -> Data {
        #if os(macOS)
        return try verifyWithCMSDecoder(blob)
        #else
        return try CMSVerifier.verify(blob, anchors: anchors)   // CMSDecoder does not exist on iOS
        #endif
    }

    #if os(macOS)
    private static func verifyWithCMSDecoder(_ blob: Data) throws -> Data {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let dec = decoder else {
            throw CardError.signature("CMS decoder")
        }
        guard blob.withUnsafeBytes({ CMSDecoderUpdateMessage(dec, $0.baseAddress!, blob.count) }) == errSecSuccess,
              CMSDecoderFinalizeMessage(dec) == errSecSuccess else {
            throw CardError.signature("cannot parse CMS")
        }

        // No revocation / no network: chain building against bundled anchors only.
        let policy = SecPolicyCreateBasicX509()
        var status = CMSSignerStatus.unsigned
        var trust: SecTrust?
        var certVerifyResult: OSStatus = 0
        guard CMSDecoderCopySignerStatus(dec, 0, policy, false, &status, &trust, &certVerifyResult) == errSecSuccess
        else { throw CardError.signature("no signer") }

        switch status {
        case .valid: break
        case .invalidSignature, .invalidIndex, .needsDetachedContent, .unsigned:
            throw CardError.signature("invalid signature (\(status.rawValue))")
        default:
            throw CardError.signature("signer status \(status.rawValue)")
        }

        guard let trust else { throw CardError.chainNotTrusted("no trust object") }
        SecTrustSetAnchorCertificates(trust, anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var err: CFError?
        guard SecTrustEvaluateWithError(trust, &err) else {
            throw CardError.chainNotTrusted((err as Error?)?.localizedDescription ?? "untrusted")
        }

        var content: CFData?
        guard CMSDecoderCopyContent(dec, &content) == errSecSuccess, let c = content else {
            throw CardError.signature("no content")
        }
        return c as Data
    }
    #endif
}
