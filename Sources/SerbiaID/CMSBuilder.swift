import Foundation
import CryptoKit

/// Builds a detached CMS SignedData (.p7s) whose RSA signature is produced by the card.
/// CMSEncoder cannot be used: the token key is not a keychain identity, so the DER is assembled by hand.
enum CMSBuilder {
    private static func tlv(_ tag: UInt8, _ content: Data) -> Data { Asn1Node.header(tag: tag, length: content.count) + content }
    private static func seq(_ parts: Data...) -> Data { tlv(0x30, parts.reduce(Data(), +)) }
    private static func set(_ parts: Data...) -> Data { tlv(0x31, parts.reduce(Data(), +)) }

    private static func oid(_ bytes: [UInt8]) -> Data { tlv(0x06, Data(bytes)) }
    private static let oidSHA256 = oid([0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01])
    private static let oidData = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01])
    private static let oidSignedData = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02])
    private static let oidContentType = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x03])
    private static let oidMessageDigest = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x04])
    private static let oidSigningTime = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x05])
    private static let oidRSA = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
    private static let nullDer = Data([0x05, 0x00])
    private static let sha256DigestInfoPrefix = Data([0x30, 0x31, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
                                                      0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20])

    /// `signDigestInfo` receives a DER DigestInfo (SHA-256) and returns the raw RSA signature.
    static func signDetached(data: Data, certDer: Data, now: Date = Date(),
                             signDigestInfo: (Data) throws -> Data) throws -> Data {
        // issuer + serial from the certificate
        let cert = try Asn1Node.parse(certDer)
        guard let tbs = cert.children.first, tbs.children.count >= 4 else { throw CardError.signature("bad certificate") }
        var kids = tbs.children[...]
        if kids.first?.tag == 0xA0 { kids = kids.dropFirst() }          // [0] version
        let k = Array(kids)
        guard k.count >= 3 else { throw CardError.signature("bad certificate") }
        let serial = k[0], issuer = k[2]                                   // serial, sigAlg, issuer
        let sid = seq(issuer.raw, serial.raw)

        let digestAlg = seq(oidSHA256, nullDer)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyMMddHHmmss'Z'"
        let messageDigest = Data(SHA256.hash(data: data))
        let attrs: [Data] = [
            seq(oidContentType, set(oidData)),
            seq(oidSigningTime, set(tlv(0x17, Data(f.string(from: now).utf8)))),
            seq(oidMessageDigest, set(tlv(0x04, messageDigest))),
        ]
        // the signature covers the attributes encoded as a SET (tag 0x31); stored with the implicit tag [0] (0xA0)
        let attrBody = attrs.sorted { $0.lexicographicallyPrecedes($1) }.reduce(Data(), +)   // DER SET OF ordering
        let toSign = tlv(0x31, attrBody)
        let hash = Data(SHA256.hash(data: toSign))
        let signature = try signDigestInfo(sha256DigestInfoPrefix + hash)

        let signerInfo = seq(Data([0x02, 0x01, 0x01]), sid, digestAlg, tlv(0xA0, attrBody),
                             seq(oidRSA, nullDer), tlv(0x04, signature))
        let signedData = seq(Data([0x02, 0x01, 0x01]), set(digestAlg), seq(oidData),
                             tlv(0xA0, certDer), set(signerInfo))
        return seq(oidSignedData, tlv(0xA0, signedData))
    }
}
