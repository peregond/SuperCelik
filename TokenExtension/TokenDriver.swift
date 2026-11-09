import Foundation
import CryptoTokenKit
import CryptoKit
import Security

// CryptoTokenKit smart-card driver for the NetSeT CardEdge applet (PKCS#15 AID A000000063504B43532D3135)
// found on Serbian ID cards, foreigner ID cards, residence permits and CardEdge USB tokens.
//
// Why it exists: on macOS, Chrome and Safari take TLS client certificates only from the keychain,
// and a smart card shows up in the keychain only through a CryptoTokenKit extension. Without one the
// card is invisible to the browser ("no certificate" on eid.gov.rs) even though Super Celik reads it.
//
// The system loads this extension when a card whose applet answers SELECT AID is inserted
// (com.apple.ctk.aid in Info.plist), so it never touches other cards. It only reads public objects
// at insertion time; the PIN is asked by macOS itself (system dialog) and only when the browser
// wants a signature.
//
// Card layout (same as srb-id-pkcs11 and Super Celik's own reader):
//   8FFF = index: [count LE16] + count * [file id LE16] of meta files
//   meta file = [class][file id BE16][label len][label][id len = 20][id]
//               class 1 = certificate, 2 = public key, 3 = private key
//   certificate file = [len LE16][01 00][uncompressed size LE16][zlib stream]
//   public key file  = 00 05 xx <private key file BE16> <modulus len BE16> <modulus> <exp len BE16> <exp>
// Signing: MSE SET 00 22 41 B6 [80 01 alg][84 02 key file], then PSO 00 2A 9E P2 <data> Le=00.
//   alg 2 = card adds PKCS#1 v1.5 padding to a DigestInfo; alg 0 = raw RSA, the first byte of the
//   256-byte block goes into P2 (that is how a full block fits a short APDU).
// PIN: VERIFY 00 20 00 80 08 <ASCII digits, 0x00-padded to 8>; 63Cx = x tries left.

let cardEdgeAID = Data([0xA0, 0x00, 0x00, 0x00, 0x63, 0x50, 0x4B, 0x43, 0x53, 0x2D, 0x31, 0x35])

enum CardIO {
    /// Sends one APDU inside an open card session, follows 61xx (GET RESPONSE) and 6Cxx (wrong Le).
    static func transmit(_ card: TKSmartCard, _ apdu: [UInt8]) throws -> (data: Data, sw: UInt16) {
        var (data, sw) = try raw(card, Data(apdu))
        if sw >> 8 == 0x6C, apdu.count >= 5 {
            var again = apdu
            again[again.count - 1] = UInt8(sw & 0xFF)
            (data, sw) = try raw(card, Data(again))
        }
        while sw >> 8 == 0x61 {
            let (more, sw2) = try raw(card, Data([0x00, 0xC0, 0x00, 0x00, UInt8(sw & 0xFF)]))
            data += more
            sw = sw2
        }
        return (data, sw)
    }

    private static func raw(_ card: TKSmartCard, _ apdu: Data) throws -> (Data, UInt16) {
        let done = DispatchSemaphore(value: 0)
        var reply: Data?
        var failure: Error?
        card.transmit(apdu) { r, e in
            reply = r
            failure = e
            done.signal()
        }
        if done.wait(timeout: .now() + 30) == .timedOut { throw TKError(.communicationError) }
        if let failure { throw failure }
        guard let reply, reply.count >= 2 else { throw TKError(.communicationError) }
        let sw = UInt16(reply[reply.count - 2]) << 8 | UInt16(reply[reply.count - 1])
        return (Data(reply.dropLast(2)), sw)
    }

    /// Runs `body` inside an exclusive card session (beginSession ... endSession).
    static func session<T>(_ card: TKSmartCard, _ body: () throws -> T) throws -> T {
        let done = DispatchSemaphore(value: 0)
        var ok = false
        var failure: Error?
        card.beginSession { success, error in
            ok = success
            failure = error
            done.signal()
        }
        if done.wait(timeout: .now() + 30) == .timedOut { throw TKError(.communicationError) }
        guard ok else { throw failure ?? TKError(.communicationError) }
        defer { card.endSession() }
        return try body()
    }

    static func selectApplet(_ card: TKSmartCard) throws {
        let r = try transmit(card, [0x00, 0xA4, 0x04, 0x00, UInt8(cardEdgeAID.count)] + [UInt8](cardEdgeAID))
        guard r.sw == 0x9000 else { throw TKError(.corruptedData) }
    }

    /// SELECT by file id; the file size is bytes 2-3 (BE) of the FCI. Then READ BINARY in chunks.
    static func readFile(_ card: TKSmartCard, _ fid: UInt16) throws -> Data {
        let sel = try transmit(card, [0x00, 0xA4, 0x00, 0x00, 0x02, UInt8(fid >> 8), UInt8(fid & 0xFF)])
        guard sel.sw == 0x9000, sel.data.count >= 4 else { throw TKError(.objectNotFound) }
        let size = Int(sel.data[sel.data.startIndex + 2]) << 8 | Int(sel.data[sel.data.startIndex + 3])
        var out = Data()
        while out.count < size {
            let n = min(0xE0, size - out.count)
            let o = out.count
            let r = try transmit(card, [0x00, 0xB0, UInt8(o >> 8), UInt8(o & 0xFF), UInt8(n)])
            guard r.sw == 0x9000, !r.data.isEmpty else { throw TKError(.corruptedData) }
            out += r.data
        }
        return out
    }

    /// zlib stream (78 xx ... adler32) -> bytes. Foundation's `.zlib` is raw deflate, so the
    /// 2-byte header and the 4-byte Adler-32 trailer are cut off first.
    static func inflate(_ zlib: Data) -> Data? {
        let z = Data(zlib)
        guard z.count > 6, z[0] == 0x78 else { return nil }
        return try? (Data(z.dropFirst(2).dropLast(4)) as NSData).decompressed(using: .zlib) as Data
    }
}

/// One certificate + private key pair found on the card.
struct CardKeyPair {
    var label: String
    var certificate: SecCertificate
    var keyFile: UInt16
    var modulusBits: Int
}

enum CardObjects {
    /// Reads all certificate / key pairs. Falls back to the fixed layout Super Celik already reads
    /// (certificate 7102, key 6005) when the index cannot be parsed.
    static func load(_ card: TKSmartCard) throws -> [CardKeyPair] {
        try CardIO.selectApplet(card)
        if let pairs = try? fromIndex(card), !pairs.isEmpty { return pairs }
        guard let blob = try? CardIO.readFile(card, 0x7102), blob.count > 8,
              let der = CardIO.inflate(blob.dropFirst(6)),
              let cert = SecCertificateCreateWithData(nil, der as CFData) else { return [] }
        return [CardKeyPair(label: SecCertificateCopySubjectSummary(cert) as String? ?? "eID",
                            certificate: cert, keyFile: 0x6005, modulusBits: bits(of: cert))]
    }

    private struct Meta { var cls: UInt8; var fid: UInt16; var label: String; var id: Data }

    private static func fromIndex(_ card: TKSmartCard) throws -> [CardKeyPair] {
        let index = [UInt8](try CardIO.readFile(card, 0x8FFF))
        guard index.count >= 2 else { return [] }
        let count = Int(index[0]) | Int(index[1]) << 8
        guard 2 + 2 * count <= index.count else { return [] }

        var metas: [Meta] = []
        for i in 0..<count {
            let fid = UInt16(index[2 + 2 * i]) | UInt16(index[3 + 2 * i]) << 8
            guard let m = try? [UInt8](CardIO.readFile(card, fid)), m.count >= 5, (1...3).contains(m[0]) else { continue }
            let labelLen = Int(m[3])
            var p = 4 + labelLen
            guard p < m.count else { continue }
            let label = String(decoding: m[4..<p], as: UTF8.self)
            let idLen = Int(m[p]); p += 1
            guard p + idLen <= m.count else { continue }
            metas.append(Meta(cls: m[0], fid: UInt16(m[1]) << 8 | UInt16(m[2]), label: label, id: Data(m[p..<(p + idLen)])))
        }

        var pairs: [CardKeyPair] = []
        for c in metas where c.cls == 1 {
            guard let pub = metas.first(where: { $0.cls == 2 && $0.id == c.id }),
                  let blob = try? CardIO.readFile(card, c.fid), blob.count > 8,
                  let der = CardIO.inflate(blob.dropFirst(6)),
                  let cert = SecCertificateCreateWithData(nil, der as CFData),
                  let pk = try? [UInt8](CardIO.readFile(card, pub.fid)), pk.count >= 7,
                  pk[0] == 0x00, pk[1] == 0x05 else { continue }
            let keyFile = UInt16(pk[3]) << 8 | UInt16(pk[4])
            let modLen = Int(pk[5]) << 8 | Int(pk[6])
            pairs.append(CardKeyPair(label: c.label.isEmpty ? (SecCertificateCopySubjectSummary(cert) as String? ?? "eID") : c.label,
                                     certificate: cert, keyFile: keyFile,
                                     modulusBits: modLen > 0 ? modLen * 8 : bits(of: cert)))
        }
        return pairs
    }

    static func bits(of cert: SecCertificate) -> Int {
        guard let key = SecCertificateCopyKey(cert),
              let attrs = SecKeyCopyAttributes(key) as? [String: Any],
              let n = attrs[kSecAttrKeySizeInBits as String] as? Int else { return 2048 }
        return n
    }
}

// MARK: - Driver

@objc(SuperCelikTokenDriver)
final class TokenDriver: TKSmartCardTokenDriver, TKSmartCardTokenDriverDelegate {
    override init() {
        super.init()
        delegate = self
    }

    func tokenDriver(_ driver: TKSmartCardTokenDriver, createTokenFor smartCard: TKSmartCard, aid AID: Data?) throws -> TKSmartCardToken {
        try Token(smartCard: smartCard, aid: AID, driver: self)
    }
}

// MARK: - Token

final class Token: TKSmartCardToken, TKTokenDelegate {
    /// Object id (Data) -> key pair info, used by the session to find the private key file.
    private(set) var pairs: [Data: CardKeyPair] = [:]

    init(smartCard: TKSmartCard, aid: Data?, driver: TokenDriver) throws {
        var found: [CardKeyPair] = []
        var serial = ""
        try CardIO.session(smartCard) {
            found = try CardObjects.load(smartCard)
            if let info = try? CardIO.readFile(smartCard, 0x70F3), info.count > 32 {
                serial = String(decoding: info.dropFirst(32).prefix { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self)
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        if serial.isEmpty {
            serial = found.first.map { Data(SHA256.hash(data: SecCertificateCopyData($0.certificate) as Data)).prefix(8)
                .map { String(format: "%02X", $0) }.joined() } ?? UUID().uuidString
        }
        super.init(smartCard: smartCard, aid: aid ?? cardEdgeAID, instanceID: "SuperCelik-" + serial, tokenDriver: driver)
        delegate = self

        var items: [TKTokenKeychainItem] = []
        for pair in found {
            let base = Data([UInt8(pair.keyFile >> 8), UInt8(pair.keyFile & 0xFF)])
            let certID = Data("cert".utf8) + base
            let keyID = Data("key".utf8) + base
            guard let certItem = TKTokenKeychainCertificate(certificate: pair.certificate, objectID: certID),
                  let keyItem = TKTokenKeychainKey(certificate: pair.certificate, objectID: keyID) else { continue }
            certItem.label = pair.label
            keyItem.label = pair.label
            keyItem.canSign = true
            keyItem.canDecrypt = false
            keyItem.canPerformKeyExchange = false
            keyItem.isSuitableForLogin = false
            keyItem.constraints = [NSNumber(value: TKTokenOperation.signData.rawValue): "PIN"]
            items += [certItem, keyItem]
            pairs[keyID] = pair
        }
        keychainContents?.fill(with: items)
    }

    func createSession(_ token: TKToken) throws -> TKTokenSession {
        TokenSession(token: self)
    }
}

// MARK: - Session

final class TokenSession: TKSmartCardTokenSession, TKTokenSessionDelegate {
    private var cardToken: Token { token as! Token }

    init(token: Token) {
        super.init(token: token)
        delegate = self
    }

    // PKCS#1 v1.5 is done by the card (alg 2), PSS (needed by TLS 1.3) and raw by us + raw RSA (alg 0).
    private static let pkcs1: [(SecKeyAlgorithm, Data, Int)] = [
        (.rsaSignatureDigestPKCS1v15SHA1, Data([0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2B, 0x0E, 0x03, 0x02, 0x1A, 0x05, 0x00, 0x04, 0x14]), 20),
        (.rsaSignatureDigestPKCS1v15SHA256, Data([0x30, 0x31, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20]), 32),
        (.rsaSignatureDigestPKCS1v15SHA384, Data([0x30, 0x41, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30]), 48),
        (.rsaSignatureDigestPKCS1v15SHA512, Data([0x30, 0x51, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40]), 64),
    ]
    private static let pss: [(SecKeyAlgorithm, PSS.Hash)] = [
        (.rsaSignatureDigestPSSSHA256, .sha256), (.rsaSignatureDigestPSSSHA384, .sha384), (.rsaSignatureDigestPSSSHA512, .sha512),
    ]

    func tokenSession(_ session: TKTokenSession, supports operation: TKTokenOperation, keyObjectID: Any, algorithm: TKTokenKeyAlgorithm) -> Bool {
        guard operation == .signData, let id = keyObjectID as? Data, cardToken.pairs[id] != nil else { return false }
        if algorithm.isAlgorithm(.rsaSignatureRaw) || algorithm.isAlgorithm(.rsaSignatureDigestPKCS1v15Raw) { return true }
        return Self.pkcs1.contains { algorithm.isAlgorithm($0.0) } || Self.pss.contains { algorithm.isAlgorithm($0.0) }
    }

    func tokenSession(_ session: TKTokenSession, sign dataToSign: Data, keyObjectID: Any, algorithm: TKTokenKeyAlgorithm) throws -> Data {
        guard let id = keyObjectID as? Data, let pair = cardToken.pairs[id] else { throw TKError(.objectNotFound) }
        let k = (pair.modulusBits + 7) / 8
        let data = Data(dataToSign)

        if algorithm.isAlgorithm(.rsaSignatureRaw), data.count == k {
            return try cardSign(pair, raw: data)
        }
        for (alg, prefix, len) in Self.pkcs1 where algorithm.isAlgorithm(alg) && data.count == len {
            return try cardSign(pair, digestInfo: prefix + data)
        }
        if algorithm.isAlgorithm(.rsaSignatureDigestPKCS1v15Raw) {
            return try cardSign(pair, digestInfo: data)
        }
        for (alg, hash) in Self.pss where algorithm.isAlgorithm(alg) && data.count == hash.length {
            let em = try PSS.encode(digest: data, hash: hash, modulusBits: pair.modulusBits)
            return try cardSign(pair, raw: Data(repeating: 0, count: k - em.count) + em)
        }
        throw TKError(.badParameter)
    }

    /// Card pads (PKCS#1 v1.5 type 1) and signs a DigestInfo.
    private func cardSign(_ pair: CardKeyPair, digestInfo: Data) throws -> Data {
        guard digestInfo.count <= 0xFF else { throw TKError(.badParameter) }
        return try perform(pair, alg: 0x02) { [0x00, 0x2A, 0x9E, 0x00, UInt8(digestInfo.count)] + [UInt8](digestInfo) + [0x00] }
    }

    /// Raw RSA on a full modulus-sized block; byte 0 goes into P2.
    private func cardSign(_ pair: CardKeyPair, raw block: Data) throws -> Data {
        let b = [UInt8](block)
        guard b.count >= 2, b.count - 1 <= 0xFF else { throw TKError(.badParameter) }
        return try perform(pair, alg: 0x00) { [0x00, 0x2A, 0x9E, b[0], UInt8(b.count - 1)] + b[1...] + [0x00] }
    }

    private func perform(_ pair: CardKeyPair, alg: UInt8, _ pso: () -> [UInt8]) throws -> Data {
        let card = smartCard
        return try CardIO.session(card) {
            // No SELECT up front: re-selecting the applet can drop the PIN that was just verified.
            // Only if another app left a different applet selected (MSE rejected) select ours again.
            let mse: [UInt8] = [0x00, 0x22, 0x41, 0xB6, 0x07, 0x80, 0x01, alg, 0x84, 0x02, UInt8(pair.keyFile >> 8), UInt8(pair.keyFile & 0xFF)]
            var m = try CardIO.transmit(card, mse)
            if m.sw != 0x9000 {
                try CardIO.selectApplet(card)
                m = try CardIO.transmit(card, mse)
            }
            guard m.sw == 0x9000 else { throw TKError(.corruptedData) }
            let r = try CardIO.transmit(card, pso())
            switch r.sw {
            case 0x9000 where !r.data.isEmpty: return r.data
            case 0x6982: throw TKError(.authenticationNeeded)   // PIN not verified yet -> system asks for it
            case 0x6983: throw TKError(.authenticationFailed)
            default: throw TKError(.corruptedData)
            }
        }
    }

    func tokenSession(_ session: TKTokenSession, beginAuthFor operation: TKTokenOperation, constraint: Any) throws -> TKTokenAuthOperation {
        let op = PINOperation()
        op.smartCard = smartCard
        let format = TKSmartCardPINFormat()
        format.charset = .numeric
        format.encoding = .ascii
        format.minPINLength = 4
        format.maxPINLength = 8
        format.pinBlockByteLength = 8
        format.pinJustification = .left
        op.pinFormat = format
        op.apduTemplate = Data([0x00, 0x20, 0x00, 0x80, 0x08, 0, 0, 0, 0, 0, 0, 0, 0])
        op.pinByteOffset = 5
        return op
    }
}

/// PIN entered in the macOS dialog -> VERIFY, sent by us so the CardEdge applet is selected first
/// and the status words map to proper errors. A wrong PIN uses up a try; it is never retried here.
final class PINOperation: TKTokenSmartCardPINAuthOperation {
    override func finish() throws {
        guard let card = smartCard, let pin = pin else { throw TKError(.canceledByUser) }
        let digits = [UInt8](pin.utf8)
        guard (4...8).contains(digits.count), digits.allSatisfy({ (0x30...0x39).contains($0) }) else {
            throw TKError(.authenticationFailed)
        }
        let block = digits + [UInt8](repeating: 0, count: 8 - digits.count)
        let sw: UInt16 = try CardIO.session(card) {
            try CardIO.selectApplet(card)
            return try CardIO.transmit(card, [0x00, 0x20, 0x00, 0x80, 0x08] + block).sw
        }
        guard sw == 0x9000 else { throw TKError(.authenticationFailed) }
    }
}

// MARK: - RSA-PSS encoding (RFC 8017 9.1.1, MGF1 with the same hash, salt length = hash length)

enum PSS {
    enum Hash {
        case sha256, sha384, sha512
        var length: Int { self == .sha256 ? 32 : self == .sha384 ? 48 : 64 }
        func digest(_ d: Data) -> Data {
            switch self {
            case .sha256: return Data(SHA256.hash(data: d))
            case .sha384: return Data(SHA384.hash(data: d))
            case .sha512: return Data(SHA512.hash(data: d))
            }
        }
    }

    static func encode(digest mHash: Data, hash: Hash, modulusBits: Int) throws -> Data {
        let emBits = modulusBits - 1
        let emLen = (emBits + 7) / 8
        let hLen = hash.length, sLen = hash.length
        guard emLen >= hLen + sLen + 2 else { throw TKError(.badParameter) }

        var salt = Data(count: sLen)
        let rc = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, sLen, $0.baseAddress!) }
        guard rc == errSecSuccess else { throw TKError(.badParameter) }

        let h = hash.digest(Data(count: 8) + mHash + salt)
        var db = [UInt8](repeating: 0, count: emLen - sLen - hLen - 2) + [0x01] + [UInt8](salt)
        let mask = mgf1(seed: h, length: db.count, hash: hash)
        for i in 0..<db.count { db[i] ^= mask[i] }
        db[0] &= UInt8(0xFF >> (8 * emLen - emBits))
        return Data(db) + h + Data([0xBC])
    }

    private static func mgf1(seed: Data, length: Int, hash: Hash) -> [UInt8] {
        var out = Data()
        var counter: UInt32 = 0
        while out.count < length {
            let c = Data([UInt8(counter >> 24), UInt8(counter >> 16 & 0xFF), UInt8(counter >> 8 & 0xFF), UInt8(counter & 0xFF)])
            out += hash.digest(seed + c)
            counter += 1
        }
        return [UInt8](out.prefix(length))
    }
}
