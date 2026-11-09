import Foundation
import Security

enum TokenCodec {
    /// zlib stream (78 xx ... adler32) -> bytes. Foundation's `.zlib` expects raw deflate,
    /// so the 2-byte header and 4-byte Adler-32 trailer are stripped first.
    static func inflate(_ zlib: Data) -> Data? {
        guard zlib.count > 6, zlib[zlib.startIndex] == 0x78 else { return nil }
        let raw = zlib.dropFirst(2).dropLast(4)
        return try? (Data(raw) as NSData).decompressed(using: .zlib) as Data
    }

    struct CertSummary {
        var subject: String
        var chainTrusted: Bool
        var chainError: String?
    }

    /// Subject summary + whether the certificate chains to the bundled MUP CAs (no revocation check).
    static func summarize(der: Data) -> CertSummary? {
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        let subject = SecCertificateCopySubjectSummary(cert) as String? ?? ""
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust else { return CertSummary(subject: subject, chainTrusted: false, chainError: "trust") }
        SecTrustSetAnchorCertificates(trust, SignatureVerifier.anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var err: CFError?
        let ok = SecTrustEvaluateWithError(trust, &err)
        return CertSummary(subject: subject, chainTrusted: ok, chainError: (err as Error?)?.localizedDescription)
    }
}
