import Foundation
import Security
import CryptoKit

// MARK: - Minimal BER/DER reader
//
// iOS has no CMSDecoder (macOS-only API), so the iOS app verifies the card's CMS signatures with
// this small parser + SecKey + SecTrust. It also reads certificate validity dates, because
// SecCertificateCopyValues is macOS-only too. Compiled on macOS as well so CI checks it there.

struct Asn1Node {
    let tag: UInt8              // single-byte tags only (all that CMS / X.509 use here)
    let raw: Data               // full encoding: header + content (+ end-of-contents for indefinite)
    let content: Data           // content octets (for constructed nodes: the encoded children)
    let children: [Asn1Node]    // parsed children of constructed nodes

    var isConstructed: Bool { tag & 0x20 != 0 }

    /// OCTET STRING value; BER allows a constructed (chunked) form, which is joined here.
    var octets: Data {
        if tag == 0x24 { return children.reduce(into: Data()) { $0 += $1.octets } }
        return content
    }

    /// Dotted OID string for an OBJECT IDENTIFIER node.
    var oid: String? {
        guard tag == 0x06, !content.isEmpty else { return nil }
        let b = [UInt8](content)
        var parts = [Int(b[0]) / 40, Int(b[0]) % 40]
        var v = 0
        for x in b.dropFirst() {
            v = v << 7 | Int(x & 0x7F)
            if x & 0x80 == 0 { parts.append(v); v = 0 }
        }
        return parts.map(String.init).joined(separator: ".")
    }

    static func parse(_ data: Data) throws -> Asn1Node {
        let bytes = [UInt8](data)
        var pos = 0
        return try parse(bytes, &pos, depth: 0)
    }

    private static func fail() -> Error { CardError.signature("cannot parse CMS") }

    private static func parse(_ b: [UInt8], _ pos: inout Int, depth: Int) throws -> Asn1Node {
        guard depth < 64, pos + 2 <= b.count else { throw fail() }
        let start = pos
        let tag = b[pos]; pos += 1
        guard tag & 0x1F != 0x1F else { throw fail() }        // multi-byte tag: not used here
        let first = b[pos]; pos += 1
        let constructed = tag & 0x20 != 0

        if first == 0x80 {                                     // indefinite length (BER)
            guard constructed else { throw fail() }
            let cStart = pos
            var kids: [Asn1Node] = []
            while true {
                guard pos + 2 <= b.count else { throw fail() }
                if b[pos] == 0 && b[pos + 1] == 0 { break }
                kids.append(try parse(b, &pos, depth: depth + 1))
            }
            let cEnd = pos
            pos += 2
            return Asn1Node(tag: tag, raw: Data(b[start..<pos]), content: Data(b[cStart..<cEnd]), children: kids)
        }

        var len = 0
        if first & 0x80 == 0 {
            len = Int(first)
        } else {
            let n = Int(first & 0x7F)
            guard n <= 4, pos + n <= b.count else { throw fail() }
            for _ in 0..<n { len = len << 8 | Int(b[pos]); pos += 1 }
        }
        guard len >= 0, pos + len <= b.count else { throw fail() }
        let cStart = pos, cEnd = pos + len
        var kids: [Asn1Node] = []
        if constructed {
            var p = cStart
            while p < cEnd {
                if p + 2 <= cEnd, b[p] == 0, b[p + 1] == 0 { break }   // stray end-of-contents
                kids.append(try parse(b, &p, depth: depth + 1))
            }
            guard p <= cEnd else { throw fail() }
        }
        pos = cEnd
        return Asn1Node(tag: tag, raw: Data(b[start..<cEnd]), content: Data(b[cStart..<cEnd]), children: kids)
    }

    /// DER header for `tag` + `length`.
    static func header(tag: UInt8, length: Int) -> Data {
        if length < 0x80 { return Data([tag, UInt8(length)]) }
        var l = length, lenBytes: [UInt8] = []
        while l > 0 { lenBytes.insert(UInt8(l & 0xFF), at: 0); l >>= 8 }
        return Data([tag, 0x80 | UInt8(lenBytes.count)] + lenBytes)
    }

    /// ASN.1 time (UTCTime / GeneralizedTime) as a Date.
    var time: Date? {
        guard tag == 0x17 || tag == 0x18, let s = String(data: content, encoding: .ascii) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = tag == 0x17 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        return f.date(from: s)
    }
}

// MARK: - Certificate validity (used on iOS)

enum X509Dates {
    /// notBefore / notAfter from an X.509 DER certificate.
    static func validity(der: Data) -> (Date?, Date?) {
        guard let cert = try? Asn1Node.parse(der), let tbs = cert.children.first else { return (nil, nil) }
        // TBSCertificate: [0] version (optional), serial, signature alg, issuer, validity, ...
        let fields = tbs.children.first?.tag == 0xA0 ? Array(tbs.children.dropFirst()) : tbs.children
        guard fields.count > 3 else { return (nil, nil) }
        let v = fields[3].children
        guard v.count == 2 else { return (nil, nil) }
        return (v[0].time, v[1].time)
    }
}

// MARK: - CMS SignedData verification without CMSDecoder (used on iOS)

enum CMSVerifier {
    private static let oidSignedData = "1.2.840.113549.1.7.2"
    private static let oidMessageDigest = "1.2.840.113549.1.9.4"

    /// Verifies a BER CMS SignedData: signature over the content (directly or through signed
    /// attributes), and the signer certificate chain against `anchors` only. Returns the content.
    static func verify(_ blob: Data, anchors: [SecCertificate]) throws -> Data {
        let bad = CardError.signature("cannot parse CMS")
        let ci = try Asn1Node.parse(blob)
        guard ci.children.count >= 2, ci.children[0].oid == oidSignedData,
              let sd = ci.children[1].children.first, sd.tag == 0x30 else { throw bad }

        // SignedData: version, digestAlgorithms, encapContentInfo, [0] certificates, [1] crls, signerInfos
        let parts = sd.children
        guard parts.count >= 4 else { throw bad }
        let encap = parts[2]
        guard let explicit = encap.children.dropFirst().first, let octet = explicit.children.first else {
            throw CardError.signature("no content")
        }
        let content = octet.octets
        let certNodes = parts.first(where: { $0.tag == 0xA0 })?.children ?? []
        let certs = certNodes.compactMap { SecCertificateCreateWithData(nil, $0.raw as CFData) }
        guard let signerInfos = parts.last, signerInfos.tag == 0x31,
              let si = signerInfos.children.first else { throw CardError.signature("no signer") }

        // SignerInfo: version, sid, digestAlgorithm, [0] signedAttrs?, signatureAlgorithm, signature, ...
        let f = si.children
        guard f.count >= 5, let digestOID = f[2].children.first?.oid else { throw bad }
        let signedAttrs = f.first(where: { $0.tag == 0xA0 })
        guard let sigIndex = f.lastIndex(where: { $0.tag == 0x04 }), sigIndex > 0,
              let sigAlgOID = f[sigIndex - 1].children.first?.oid else { throw bad }
        let signature = f[sigIndex].octets

        guard let hash = digest(digestOID) else {
            throw CardError.signature("unsupported digest \(digestOID)")
        }

        var signedBytes = content
        if let attrs = signedAttrs {
            // messageDigest attribute must equal hash(content)
            let md = attrs.children.first { $0.children.first?.oid == oidMessageDigest }
            guard let value = md?.children.dropFirst().first?.children.first?.octets,
                  value == hash.fn(content) else {
                throw CardError.signature("invalid signature (message digest)")
            }
            // The signature covers the DER of the attributes with an explicit SET OF tag.
            let body = attrs.children.reduce(into: Data()) { $0 += $1.raw }
            signedBytes = Asn1Node.header(tag: 0x31, length: body.count) + body
        }

        guard let algorithm = secAlgorithm(sigAlgOID, digest: hash.name) else {
            throw CardError.signature("unsupported signature algorithm \(sigAlgOID)")
        }
        // Use the embedded certificate whose key verifies the signature.
        guard let signer = certs.first(where: { cert in
            guard let key = SecCertificateCopyKey(cert) else { return false }
            return SecKeyVerifySignature(key, algorithm, signedBytes as CFData, signature as CFData, nil)
        }) else { throw CardError.signature("invalid signature") }

        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(([signer] + certs) as CFArray, policy, &trust) == errSecSuccess,
              let trust else { throw CardError.chainNotTrusted("no trust object") }
        SecTrustSetAnchorCertificates(trust, anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetNetworkFetchAllowed(trust, false)
        var err: CFError?
        guard SecTrustEvaluateWithError(trust, &err) else {
            throw CardError.chainNotTrusted((err as Error?)?.localizedDescription ?? "untrusted")
        }
        return content
    }

    private static func digest(_ oid: String) -> (name: String, fn: (Data) -> Data)? {
        switch oid {
        case "2.16.840.1.101.3.4.2.1": return ("SHA256", { Data(SHA256.hash(data: $0)) })
        case "2.16.840.1.101.3.4.2.2": return ("SHA384", { Data(SHA384.hash(data: $0)) })
        case "2.16.840.1.101.3.4.2.3": return ("SHA512", { Data(SHA512.hash(data: $0)) })
        case "1.3.14.3.2.26": return ("SHA1", { Data(Insecure.SHA1.hash(data: $0)) })
        default: return nil
        }
    }

    private static func secAlgorithm(_ oid: String, digest: String) -> SecKeyAlgorithm? {
        let rsa = ["1.2.840.113549.1.1.1", "1.2.840.113549.1.1.5", "1.2.840.113549.1.1.11",
                   "1.2.840.113549.1.1.12", "1.2.840.113549.1.1.13"]
        let ec = ["1.2.840.10045.2.1", "1.2.840.10045.4.1", "1.2.840.10045.4.3.2",
                  "1.2.840.10045.4.3.3", "1.2.840.10045.4.3.4"]
        if rsa.contains(oid) {
            switch digest {
            case "SHA1": return .rsaSignatureMessagePKCS1v15SHA1
            case "SHA384": return .rsaSignatureMessagePKCS1v15SHA384
            case "SHA512": return .rsaSignatureMessagePKCS1v15SHA512
            default: return .rsaSignatureMessagePKCS1v15SHA256
            }
        }
        if oid == "1.2.840.113549.1.1.10" {          // RSASSA-PSS, salt length = hash length
            switch digest {
            case "SHA384": return .rsaSignatureMessagePSSSHA384
            case "SHA512": return .rsaSignatureMessagePSSSHA512
            default: return .rsaSignatureMessagePSSSHA256
            }
        }
        if ec.contains(oid) {
            switch digest {
            case "SHA1": return .ecdsaSignatureMessageX962SHA1
            case "SHA384": return .ecdsaSignatureMessageX962SHA384
            case "SHA512": return .ecdsaSignatureMessageX962SHA512
            default: return .ecdsaSignatureMessageX962SHA256
            }
        }
        return nil
    }
}
