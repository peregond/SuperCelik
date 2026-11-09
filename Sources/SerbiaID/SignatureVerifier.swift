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
        let urls = Bundle.module.urls(forResourcesWithExtension: "crt", subdirectory: "Resources/CA") ?? []
        return urls.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        }
    }()

    /// Verifies a BER CMS SignedData: signature, signer certificate chain (MUP CAs only).
    /// Returns the signed content.
    static func verifyCMS(_ blob: Data) throws -> Data {
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
}
