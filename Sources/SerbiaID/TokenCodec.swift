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
        var issuer: String = ""
        var notBefore: Date?
        var notAfter: Date?
        var chainTrusted: Bool
        var chainError: String?
    }

    /// Subject, issuer (matched against the bundled MUP CAs), validity and whether the certificate
    /// chains to those CAs (no revocation check).
    static func summarize(der: Data) -> CertSummary? {
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        let subject = SecCertificateCopySubjectSummary(cert) as String? ?? ""
        let (issuer, from, to) = details(of: cert)

        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust else {
            return CertSummary(subject: subject, issuer: issuer, notBefore: from, notAfter: to, chainTrusted: false, chainError: "trust")
        }
        SecTrustSetAnchorCertificates(trust, SignatureVerifier.anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var err: CFError?
        let ok = SecTrustEvaluateWithError(trust, &err)
        return CertSummary(subject: subject, issuer: issuer, notBefore: from, notAfter: to,
                           chainTrusted: ok, chainError: (err as Error?)?.localizedDescription)
    }

    private static func details(of cert: SecCertificate) -> (String, Date?, Date?) {
        var issuer = ""
        if let ni = SecCertificateCopyNormalizedIssuerSequence(cert) as Data? {
            for ca in SignatureVerifier.anchors {
                if (SecCertificateCopyNormalizedSubjectSequence(ca) as Data?) == ni {
                    issuer = SecCertificateCopySubjectSummary(ca) as String? ?? ""
                    break
                }
            }
        }
        let oids = [kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter] as CFArray
        let vals = SecCertificateCopyValues(cert, oids, nil) as? [String: Any]
        func date(_ oid: CFString) -> Date? {
            guard let d = vals?[oid as String] as? [String: Any],
                  let n = d[kSecPropertyKeyValue as String] as? NSNumber else { return nil }
            return Date(timeIntervalSinceReferenceDate: n.doubleValue)
        }
        return (issuer, date(kSecOIDX509V1ValidityNotBefore), date(kSecOIDX509V1ValidityNotAfter))
    }
}
