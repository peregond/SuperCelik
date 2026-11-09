import Foundation
import PCSC

// MARK: - Data model (mirrors CelikApi 1.4.2 structures, see MUP "Opis funkcija")

/// EidBeginRead -> pnCardType
enum EidCardType: Int {
    case id2008 = 1   // old ID card, Apollo OS
    case id2014 = 2   // new ID card, Gemalto / Veridos
    case if2020 = 3   // ID card for foreigners
    case rp2024 = 4   // residence permit
}

struct DocumentData {                       // EID_DOCUMENT_DATA
    var docRegNo = "", documentType = "", issuingDate = "", expiryDate = ""
    var issuingAuthority = "", documentSerialNumber = "", chipSerialNumber = "", documentName = ""
}

struct FixedPersonalData {                  // EID_FIXED_PERSONAL_DATA
    var personalNumber = "", surname = "", givenName = "", parentGivenName = ""
    var sex = "", placeOfBirth = "", stateOfBirth = "", dateOfBirth = "", communityOfBirth = ""
    var statusOfForeigner = "", nationalityFull = "", purposeOfStay = "", eNote = ""
}

struct VariablePersonalData {               // EID_VARIABLE_PERSONAL_DATA
    var state = "", community = "", place = "", street = "", houseNumber = ""
    var houseLetter = "", entrance = "", floor = "", apartmentNumber = ""
    var addressDate = "", addressLabel = ""

    var formatted: String {
        let house = houseNumber + houseLetter
        var parts = [[street, house].filter { !$0.isEmpty }.joined(separator: " ")]
        if !entrance.isEmpty { parts.append("ul. \(entrance)") }
        if !floor.isEmpty { parts.append("sprat \(floor)") }
        if !apartmentNumber.isEmpty { parts.append("stan \(apartmentNumber)") }
        parts += [place, community, state]
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct PersonalData {
    var cardType: EidCardType = .id2014
    var document = DocumentData()
    var fixed = FixedPersonalData()
    var variable = VariablePersonalData()
    var portrait: Data?                     // JPEG
}

/// EID_Cert_* ; the first three exist only on the old (Apollo) card,
/// the last two only on newer cards.
enum EidCertType: CaseIterable {
    case moiIntermediateCA, user1Auth, user2Sign, sigFixed, sigVariable
    var appliesToOldCard: Bool { [.moiIntermediateCA, .user1Auth, .user2Sign].contains(self) }
}

/// EID_SIG_* ; portrait signature exists only on the old card.
enum EidSignature { case card, fixed, variable, portrait }

struct CertificateInfo: Identifiable {
    let id = UUID()
    var type: EidCertType
    var der: Data                           // X.509 DER
}

/// Info from the NetSeT CardEdge token (PKCS#15-style applet, MS minidriver file layout).
struct TokenInfo {
    var tokenLabel = ""            // e.g. "NetSeT's CardEdge Token"
    var tokenSerial = ""
    var certificates: [TokenCertificate] = []
}

struct TokenCertificate: Identifiable {
    let id = UUID()
    var label: String
    var der: Data                  // X.509 DER (decompressed)
}

enum CardError: LocalizedError {
    case pcsc(Int32, String)
    case notImplemented
    case unsupportedForCard
    case signature(String)          // data was tampered / signature invalid
    case chainNotTrusted(String)    // like EID_E_SECFORMAT_CHECK_CERT_ERROR: not proof the data is bad
    case pinWrong(triesLeft: Int)
    case pinBlocked
    var errorDescription: String? {
        switch self {
        case .pinWrong(let n): return "Wrong PIN, \(n) tries left"
        case .pinBlocked: return "PIN is blocked (unblock at MUP)"
        case .signature(let m): return "Signature: " + m
        case .chainNotTrusted(let m): return "Certificate chain: " + m
        case .pcsc(let code, let what): return "\(what): PC/SC 0x" + String(UInt32(bitPattern: code), radix: 16)
        case .notImplemented: return "Not implemented"
        case .unsupportedForCard: return "Not supported for this card type"
        }
    }
}

/// Everything the UI needs from a card. Swap the implementation without touching views.
protocol CardService {
    func listReaders() throws -> [String]
    func atr(reader: String) throws -> Data?          // nil = no card
    func readPersonalData(reader: String) throws -> PersonalData
    func readCertificates(reader: String, cardType: EidCardType) throws -> [CertificateInfo]
    func verify(reader: String, signature: EidSignature) throws -> Bool
    func readToken(reader: String) throws -> TokenInfo
    /// Token PIN operations. PIN = 4...8 ASCII digits. WARNING: each wrong PIN uses up one of a
    /// few tries; the card blocks at zero. Callers must never retry automatically.
    func changeTokenPin(reader: String, old: String, new: String) throws
    /// RSA PKCS#1 v1.5 signature over `digestInfo` (DER DigestInfo = hash OID + hash).
    func tokenSign(reader: String, pin: String, keyFile: UInt16, digestInfo: Data) throws -> Data
    /// Per the official API this works only on the old (Apollo) card, 5...16 chars, ISO-8859-1.
    func changePin(reader: String, cardType: EidCardType, old: String, new: String) throws -> Int
}

// MARK: - PC/SC implementation

final class PCSCService: CardService {
    private var ctx = SCARDCONTEXT()

    init() {
        _ = SCardEstablishContext(DWORD(SCARD_SCOPE_SYSTEM), nil, nil, &ctx)
    }
    deinit { SCardReleaseContext(ctx) }

    func listReaders() throws -> [String] {
        var len = DWORD(0)
        var rc = SCardListReaders(ctx, nil, nil, &len)
        if UInt32(bitPattern: rc) == 0x8010002E { return [] } // SCARD_E_NO_READERS_AVAILABLE
        guard rc == 0, len > 0 else { throw CardError.pcsc(rc, "ListReaders") }
        var buf = [CChar](repeating: 0, count: Int(len))
        rc = SCardListReaders(ctx, nil, &buf, &len)
        guard rc == 0 else { throw CardError.pcsc(rc, "ListReaders") }
        return buf.split(separator: 0).map { String(cString: Array($0) + [0]) }
    }

    func withCard<T>(reader: String, _ body: (SCARDHANDLE, DWORD) throws -> T) throws -> T {
        var card = SCARDHANDLE()
        var proto = DWORD(0)
        let rc = SCardConnect(ctx, reader, DWORD(SCARD_SHARE_SHARED),
                              DWORD(SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1), &card, &proto)
        guard rc == 0 else { throw CardError.pcsc(rc, "Connect") }
        defer { SCardDisconnect(card, DWORD(SCARD_LEAVE_CARD)) }
        return try body(card, proto)
    }

    func atr(reader: String) throws -> Data? {
        do {
            return try withCard(reader: reader) { card, _ in
                var len = DWORD(64)
                var buf = [UInt8](repeating: 0, count: 64)
                let rc = SCardGetAttrib(card, DWORD(SCARD_ATTR_ATR_STRING), &buf, &len)
                guard rc == 0 else { throw CardError.pcsc(rc, "GetAttrib") }
                return Data(buf.prefix(Int(len)))
            }
        } catch CardError.pcsc(let code, _) where UInt32(bitPattern: code) == 0x8010000C { // NO_SMARTCARD
            return nil
        }
    }

    func transmit(card: SCARDHANDLE, proto: DWORD, apdu: [UInt8]) throws -> (data: [UInt8], sw: UInt16) {
        var pci = SCARD_IO_REQUEST(dwProtocol: proto, cbPciLength: DWORD(MemoryLayout<SCARD_IO_REQUEST>.size))
        var out = [UInt8](repeating: 0, count: 4096)
        var outLen = DWORD(out.count)
        let rc = SCardTransmit(card, &pci, apdu, DWORD(apdu.count), nil, &out, &outLen)
        guard rc == 0, outLen >= 2 else { throw CardError.pcsc(rc, "Transmit") }
        let n = Int(outLen)
        return (Array(out[0..<(n - 2)]), UInt16(out[n - 2]) << 8 | UInt16(out[n - 1]))
    }

    // MARK: Card-specific part
    // Derived by observing CelikApi.dll and a real card (residence permit, SERRP applet).
    // Applet AIDs come from the DLL; file IDs / tags were verified against the DLL's output
    // for the RP2024 card only. Items marked UNVERIFIED are inferred from tag sequence.

    private static let applets: [(EidCardType, String)] = [
        (.id2014, "F381000002534552494401"),   // SERID
        (.if2020, "F381000002534552494601"),   // SERIF
        (.rp2024, "F381000002534552525001"),   // SERRP
    ]

    private func selectApplet(card: SCARDHANDLE, proto: DWORD) throws -> EidCardType {
        for (type, aid) in Self.applets {
            let a = Self.bytes(hex: aid)
            let r = try transmit(card: card, proto: proto, apdu: [0x00, 0xA4, 0x04, 0x00, UInt8(a.count)] + a)
            if r.sw == 0x9000 { return type }
        }
        throw CardError.unsupportedForCard   // e.g. old Apollo card: protocol not known
    }

    /// File = 2-byte id (LE) + 2-byte length (LE) + body. Body = records of tag(LE16) len(LE16) value.
    private func readFile(card: SCARDHANDLE, proto: DWORD, fid: UInt16) throws -> [UInt16: Data] {
        Self.parseRecords(try readRawFile(card: card, proto: proto, fid: fid))
    }

    /// Whole file including the 4-byte header (this is what the card's hashes cover).
    private func readRawFile(card: SCARDHANDLE, proto: DWORD, fid: UInt16) throws -> Data {
        var r = try transmit(card: card, proto: proto, apdu: [0x00, 0xA4, 0x00, 0x0C, 0x02, UInt8(fid >> 8), UInt8(fid & 0xFF)])
        guard r.sw == 0x9000 else { throw CardError.pcsc(Int32(r.sw), "Select file") }
        r = try transmit(card: card, proto: proto, apdu: [0x00, 0xB0, 0x00, 0x00, 0x04])
        guard r.sw == 0x9000, r.data.count == 4 else { throw CardError.pcsc(Int32(r.sw), "Read header") }
        let total = 4 + Int(r.data[2]) + Int(r.data[3]) << 8
        var data = r.data
        while data.count < total {
            let n = min(0xE0, total - data.count)
            let o = data.count
            r = try transmit(card: card, proto: proto, apdu: [0x00, 0xB0, UInt8(o >> 8), UInt8(o & 0xFF), UInt8(n)])
            guard r.sw == 0x9000 else { throw CardError.pcsc(Int32(r.sw), "Read binary") }
            data += r.data
        }
        return Data(data)
    }

    private static func parseRecords(_ data: Data) -> [UInt16: Data] {
        var out: [UInt16: Data] = [:]
        var p = 4
        while p + 4 <= data.count {
            let tag = UInt16(data[p]) | UInt16(data[p + 1]) << 8
            let len = Int(data[p + 2]) | Int(data[p + 3]) << 8
            guard p + 4 + len <= data.count else { break }
            out[tag] = Data(data[(p + 4)..<(p + 4 + len)])
            p += 4 + len
        }
        return out
    }

    private static func bytes(hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map {
            let s = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[s..<hex.index(s, offsetBy: 2)], radix: 16)!
        }
    }

    private static func str(_ d: Data?) -> String { d.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    /// Card stores dates as DDMMYYYY; the official API shows DD.MM.YYYY
    private static func date(_ d: Data?) -> String {
        let s = str(d)
        guard s.count == 8 else { return s }
        return "\(s.prefix(2)).\(s.dropFirst(2).prefix(2)).\(s.suffix(4))"
    }

    func readPersonalData(reader: String) throws -> PersonalData {
        try withCard(reader: reader) { card, proto in
            var p = PersonalData()
            p.cardType = try selectApplet(card: card, proto: proto)
            let doc = try readFile(card: card, proto: proto, fid: 0x0F02)
            let fixed = try readFile(card: card, proto: proto, fid: 0x0F03)
            let variable = try readFile(card: card, proto: proto, fid: 0x0F04)
            let s = Self.str, dt = Self.date

            // VERIFIED against CelikApi.dll output (RP2024 card)
            p.document = DocumentData(docRegNo: s(doc[0x060A]), documentType: s(doc[0x060B]),
                                      issuingDate: dt(doc[0x060D]), expiryDate: dt(doc[0x060E]),
                                      issuingAuthority: s(doc[0x060F]), documentSerialNumber: s(doc[0x0691]),
                                      chipSerialNumber: "", documentName: s(doc[0x0692]))
            p.fixed = FixedPersonalData(personalNumber: s(fixed[0x0616]), surname: s(fixed[0x0617]),
                                        givenName: s(fixed[0x0618]),
                                        parentGivenName: s(fixed[0x0619]),        // UNVERIFIED tag
                                        sex: s(fixed[0x061A]),
                                        placeOfBirth: s(fixed[0x061B]),           // UNVERIFIED tag
                                        stateOfBirth: s(fixed[0x061D]),
                                        dateOfBirth: dt(fixed[0x061E]),
                                        communityOfBirth: s(fixed[0x061C]),       // UNVERIFIED tag
                                        statusOfForeigner: "",                    // tag unknown
                                        nationalityFull: s(fixed[0x062F]),
                                        purposeOfStay: s(fixed[0x0693]), eNote: s(fixed[0x0694]))
            p.variable = VariablePersonalData(state: s(variable[0x0620]),           // UNVERIFIED tag
                                              community: s(variable[0x0621]), place: s(variable[0x0622]),
                                              street: s(variable[0x0623]), houseNumber: s(variable[0x0624]),
                                              houseLetter: s(variable[0x0625]),     // UNVERIFIED tag
                                              entrance: s(variable[0x0626]),        // UNVERIFIED tag
                                              floor: s(variable[0x0627]),           // UNVERIFIED tag
                                              apartmentNumber: s(variable[0x0628]), // UNVERIFIED tag
                                              addressDate: dt(variable[0x062C]), addressLabel: "")
            // Portrait: file 0x0F06, record tag 0x0110 = JPEG (verified)
            p.portrait = try readFile(card: card, proto: proto, fid: 0x0F06)[0x0110]
            return p
        }
    }

    /// Certificates are stored inside a BER CMS blob; the X.509 DER follows an `A0 80` marker.
    func readCertificates(reader: String, cardType: EidCardType) throws -> [CertificateInfo] {
        try withCard(reader: reader) { card, proto in
            _ = try selectApplet(card: card, proto: proto)
            var result: [CertificateInfo] = []
            for (fid, tag, type) in [(UInt16(0x0F1C), UInt16(0x0810), EidCertType.sigFixed),
                                     (UInt16(0x0F1D), UInt16(0x0820), EidCertType.sigVariable)] {
                guard let blob = try? readFile(card: card, proto: proto, fid: fid)[tag],
                      let der = Self.extractCertificate(from: blob) else { continue }
                result.append(CertificateInfo(type: type, der: der))
            }
            return result
        }
    }

    private static func extractCertificate(from b: Data) -> Data? {
        let a = [UInt8](b)
        guard a.count > 8 else { return nil }
        for i in 0..<(a.count - 8) where a[i] == 0xA0 && a[i + 1] == 0x80 && a[i + 2] == 0x30 && a[i + 3] == 0x82 {
            let len = Int(a[i + 4]) << 8 | Int(a[i + 5])
            let end = i + 2 + 4 + len
            if end <= a.count { return Data(a[(i + 2)..<end]) }
        }
        return nil
    }
    // MARK: Token (PKCS#15 applet A000000063504B43532D3135) — read-only, no PIN needed.
    // Layout observed on a NetSeT CardEdge token (MS minidriver style):
    //   70F3 = label (32 bytes, space padded) + serial; 7102 = user certificate:
    //   [len LE16][01 00][uncompressed size LE16][zlib stream] -> X.509 DER (verified, chain OK);
    //   8007 = [01 71 02 len] + certificate label. File size comes from bytes 2-3 (BE) of the SELECT FCI.
    // Private-key files (6005, 8xxx) and any PIN operation are deliberately NOT touched.

    private func readTokenFile(card: SCARDHANDLE, proto: DWORD, fid: UInt16) throws -> Data {
        let sel = try transmit(card: card, proto: proto, apdu: [0x00, 0xA4, 0x00, 0x00, 0x02, UInt8(fid >> 8), UInt8(fid & 0xFF)])
        guard sel.sw == 0x9000, sel.data.count >= 4 else { throw CardError.pcsc(Int32(sel.sw), "Select token file") }
        let size = Int(sel.data[2]) << 8 | Int(sel.data[3])
        var out = Data()
        while out.count < size {
            let n = min(0xE0, size - out.count)
            let o = out.count
            let r = try transmit(card: card, proto: proto, apdu: [0x00, 0xB0, UInt8(o >> 8), UInt8(o & 0xFF), UInt8(n)])
            guard r.sw == 0x9000 else { throw CardError.pcsc(Int32(r.sw), "Read token file") }
            out += r.data
        }
        return out
    }

    func readToken(reader: String) throws -> TokenInfo {
        try withCard(reader: reader) { card, proto in
            let aid = Self.bytes(hex: "A000000063504B43532D3135")
            let r = try transmit(card: card, proto: proto, apdu: [0x00, 0xA4, 0x04, 0x00, UInt8(aid.count)] + aid)
            guard r.sw == 0x9000 else { throw CardError.unsupportedForCard }

            var info = TokenInfo()
            if let d = try? readTokenFile(card: card, proto: proto, fid: 0x70F3), d.count > 32 {
                info.tokenLabel = (String(data: d.prefix(32), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespaces)
                info.tokenSerial = (String(data: d.dropFirst(32).prefix { $0 >= 0x20 && $0 < 0x7F }, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespaces)
            }
            if let blob = try? readTokenFile(card: card, proto: proto, fid: 0x7102), blob.count > 8,
               let der = TokenCodec.inflate(Data(blob.dropFirst(6))) {
                var label = ""
                if let l = try? readTokenFile(card: card, proto: proto, fid: 0x8007), l.count > 4 {
                    let len = Int(l[3])
                    label = String(data: l[4..<min(l.count, 4 + len)], encoding: .utf8) ?? ""
                }
                info.certificates.append(TokenCertificate(label: label, der: der))
            }
            return info
        }
    }

    // MARK: Token PIN + signing.
    // APDUs confirmed two ways: (1) headers `00 22 41 B6` (MSE SET) and `B0 83` appear in the original
    // netsetpkcs11_x64.dll; (2) live on an RP2024 card: MSE SET with key file 0x6005 -> 9000,
    // PSO without PIN -> 6982. PIN VERIFY / CHANGE formats follow the open-source srb-id-pkcs11 module
    // (same card family, same ATR) and were NOT exercised live (a wrong PIN burns a try).
    //   VERIFY:  00 20 00 80 08 <PIN digits, 0x00-padded to 8>   (63Cx = x tries left, 6983 = blocked)
    //   CHANGE:  00 24 00 80 10 <old padded 8><new padded 8>
    //   SIGN:    00 22 41 B6 07 80 01 02 84 02 <key file hi lo>, then 00 2A 9E 00 Lc <DigestInfo> 00
    // Key files: index 0x8FFF -> meta files (class 1 cert / 2 pub key / 3 priv key); public key file
    // 0x6004 = 00 05 <priv key file id> <modulus len BE16> <modulus> <exp len BE16> <exp>.

    private static func paddedPin(_ pin: String) throws -> [UInt8] {
        let b = Array(pin.utf8)
        guard (4...8).contains(b.count), b.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else {
            throw CardError.signature("PIN must be 4-8 digits")
        }
        return b + [UInt8](repeating: 0, count: 8 - b.count)
    }

    private func txFollow(card: SCARDHANDLE, proto: DWORD, apdu: [UInt8]) throws -> (data: [UInt8], sw: UInt16) {
        var r = try transmit(card: card, proto: proto, apdu: apdu)
        var data = r.data
        while r.sw >> 8 == 0x61 {   // T=0 "more data": GET RESPONSE
            r = try transmit(card: card, proto: proto, apdu: [0x00, 0xC0, 0x00, 0x00, UInt8(r.sw & 0xFF)])
            data += r.data
        }
        return (data, r.sw)
    }

    private func verifyPin(card: SCARDHANDLE, proto: DWORD, pin: String) throws {
        let r = try txFollow(card: card, proto: proto, apdu: [0x00, 0x20, 0x00, 0x80, 0x08] + (try Self.paddedPin(pin)))
        if r.sw == 0x9000 { return }
        if r.sw == 0x6983 || r.sw == 0x63C0 { throw CardError.pinBlocked }
        if r.sw >> 4 == 0x063C { throw CardError.pinWrong(triesLeft: Int(r.sw & 0xF)) }
        throw CardError.pcsc(Int32(r.sw), "Verify PIN")
    }

    private func selectTokenApplet(card: SCARDHANDLE, proto: DWORD) throws {
        let aid = Self.bytes(hex: "A000000063504B43532D3135")
        let r = try transmit(card: card, proto: proto, apdu: [0x00, 0xA4, 0x04, 0x00, UInt8(aid.count)] + aid)
        guard r.sw == 0x9000 else { throw CardError.unsupportedForCard }
    }

    func changeTokenPin(reader: String, old: String, new: String) throws {
        let data = try Self.paddedPin(old) + Self.paddedPin(new)
        try withCard(reader: reader) { card, proto in
            try selectTokenApplet(card: card, proto: proto)
            let r = try txFollow(card: card, proto: proto, apdu: [0x00, 0x24, 0x00, 0x80, 0x10] + data)
            if r.sw == 0x9000 { return }
            if r.sw == 0x6983 || r.sw == 0x63C0 { throw CardError.pinBlocked }
            if r.sw >> 4 == 0x063C { throw CardError.pinWrong(triesLeft: Int(r.sw & 0xF)) }
            throw CardError.pcsc(Int32(r.sw), "Change PIN")
        }
    }

    func tokenSign(reader: String, pin: String, keyFile: UInt16, digestInfo: Data) throws -> Data {
        guard digestInfo.count <= 255 else { throw CardError.signature("digest too long") }
        return try withCard(reader: reader) { card, proto in
            try selectTokenApplet(card: card, proto: proto)
            try verifyPin(card: card, proto: proto, pin: pin)        // single attempt, never retried
            let mse: [UInt8] = [0x80, 0x01, 0x02, 0x84, 0x02, UInt8(keyFile >> 8), UInt8(keyFile & 0xFF)]
            var r = try txFollow(card: card, proto: proto, apdu: [0x00, 0x22, 0x41, 0xB6, UInt8(mse.count)] + mse)
            guard r.sw == 0x9000 else { throw CardError.pcsc(Int32(r.sw), "MSE SET") }
            r = try txFollow(card: card, proto: proto,
                             apdu: [0x00, 0x2A, 0x9E, 0x00, UInt8(digestInfo.count)] + [UInt8](digestInfo) + [0x00])
            guard r.sw == 0x9000, !r.data.isEmpty else { throw CardError.pcsc(Int32(r.sw), "Sign") }
            return Data(r.data)
        }
    }

    /// Card signatures (verified against CelikApi.dll on an RP2024 card):
    /// file 0F1C = CMS SignedData whose content is a list of SHA-256 hashes of whole files
    /// (0F1B, 0F02, 0F03, 0F06, ..., 0FA1, 0FA2); file 0F1D = CMS whose content is SHA-256 of file 0F04.
    /// The CMS signer certificate must chain to a MUP CA bundled in Resources/CA.
    func verify(reader: String, signature: EidSignature) throws -> Bool {
        if signature == .portrait { throw CardError.unsupportedForCard }  // new cards: covered by .fixed
        return try withCard(reader: reader) { card, proto in
            _ = try selectApplet(card: card, proto: proto)
            let (cmsFile, cmsTag, covered): (UInt16, UInt16, [UInt16]) = {
                switch signature {
                case .variable: return (0x0F1D, 0x0820, [0x0F04])
                case .card: return (0x0F1C, 0x0810, [0x0F02])
                default: return (0x0F1C, 0x0810, [0x0F1B, 0x0F02, 0x0F03, 0x0F06, 0x0FA1, 0x0FA2])
                }
            }()
            guard let blob = try readFile(card: card, proto: proto, fid: cmsFile)[cmsTag] else {
                throw CardError.signature("signature block missing")
            }
            let content = try SignatureVerifier.verifyCMS(blob)          // throws if sig/chain bad
            for fid in covered {
                let raw = try readRawFile(card: card, proto: proto, fid: fid)
                guard SignatureVerifier.sha256(raw).isSubset(of: content) else {
                    throw CardError.signature(String(format: "hash mismatch for file %04X", fid))
                }
            }
            return true
        }
    }

    func changePin(reader: String, cardType: EidCardType, old: String, new: String) throws -> Int {
        guard cardType == .id2008 else { throw CardError.unsupportedForCard }
        guard (5...16).contains(new.count), new.canBeConverted(to: .isoLatin1) else { throw CardError.notImplemented }
        throw CardError.notImplemented
    }
}

// MARK: - Demo

final class MockCardService: CardService {
    func listReaders() throws -> [String] { ["Demo Reader"] }
    func atr(reader: String) throws -> Data? { Data([0x3B, 0xF9, 0x13, 0x00, 0x00]) }
    func readPersonalData(reader: String) throws -> PersonalData {
        var p = PersonalData()
        p.document = DocumentData(docRegNo: "001234567", documentType: "ID", issuingDate: "01.01.2024.",
                                  expiryDate: "01.01.2034.", issuingAuthority: "MUP RS")
        p.fixed = FixedPersonalData(personalNumber: "0101990710000", surname: "PETROVIĆ", givenName: "MARKO",
                                    parentGivenName: "Nikola", sex: "M", placeOfBirth: "Beograd",
                                    stateOfBirth: "Srbija", dateOfBirth: "01.01.1990.", communityOfBirth: "Stari Grad")
        p.variable = VariablePersonalData(state: "Srbija", community: "Stari Grad", place: "Beograd",
                                          street: "Knez Mihailova", houseNumber: "1")
        return p
    }
    func readCertificates(reader: String, cardType: EidCardType) throws -> [CertificateInfo] {
        [CertificateInfo(type: .sigFixed, der: Data())]
    }
    func verify(reader: String, signature: EidSignature) throws -> Bool { true }
    func readToken(reader: String) throws -> TokenInfo {
        TokenInfo(tokenLabel: "NetSeT's CardEdge Token", tokenSerial: "RP000000000", certificates: [])
    }
    func changePin(reader: String, cardType: EidCardType, old: String, new: String) throws -> Int { 3 }
    func changeTokenPin(reader: String, old: String, new: String) throws {}
    func tokenSign(reader: String, pin: String, keyFile: UInt16, digestInfo: Data) throws -> Data { Data(count: 256) }
}
