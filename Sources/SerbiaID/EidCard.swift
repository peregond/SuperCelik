import Foundation

// MARK: - Card protocol, independent of how APDUs reach the card
//
// Shared by the macOS app (PC/SC reader, see PCSCService) and the iOS app (NFC, see
// ios/SuperCelik/NFCCardReader.swift). Everything here only talks to the card through
// `transmit`, so both platforms run exactly the same parsing and verification code.
//
// Derived by observing CelikApi.dll and a real card (residence permit, SERRP applet).
// Applet AIDs come from the DLL; file IDs / tags were verified against the DLL's output
// for the RP2024 card only. Items marked UNVERIFIED are inferred from tag sequence.

final class EidCard {
    typealias Response = (data: [UInt8], sw: UInt16)

    /// Sends one APDU (header + body) and returns the response data and status word.
    private let transmit: ([UInt8]) throws -> Response
    /// Raw files already read during this connection. An NFC read is slow, so reading the data
    /// and then verifying the signatures in the same session must not fetch the photo twice.
    private var rawCache: [UInt16: Data] = [:]

    init(transmit: @escaping ([UInt8]) throws -> Response) {
        self.transmit = transmit
    }

    /// Applet AIDs of the eID cards. The iOS Info.plist lists the same values
    /// (com.apple.developer.nfc.readersession.iso7816.select-identifiers); keep them in sync.
    static let applets: [(EidCardType, String)] = [
        (.id2014, "F381000002534552494401"),   // SERID
        (.if2020, "F381000002534552494601"),   // SERIF
        (.rp2024, "F381000002534552525001"),   // SERRP
    ]
    static let tokenAID = "A000000063504B43532D3135"   // PKCS#15 (NetSeT CardEdge)

    @discardableResult
    func selectApplet() throws -> EidCardType {
        for (type, aid) in Self.applets {
            let a = Self.bytes(hex: aid)
            let r = try transmit([0x00, 0xA4, 0x04, 0x00, UInt8(a.count)] + a)
            if r.sw == 0x9000 { return type }
        }
        throw CardError.unsupportedForCard   // e.g. old Apollo card: protocol not known
    }

    /// File = 2-byte id (LE) + 2-byte length (LE) + body. Body = records of tag(LE16) len(LE16) value.
    private func readFile(fid: UInt16) throws -> [UInt16: Data] {
        Self.parseRecords(try readRawFile(fid: fid))
    }

    /// Whole file including the 4-byte header (this is what the card's hashes cover).
    private func readRawFile(fid: UInt16) throws -> Data {
        if let d = rawCache[fid] { return d }
        var r = try transmit([0x00, 0xA4, 0x00, 0x0C, 0x02, UInt8(fid >> 8), UInt8(fid & 0xFF)])
        guard r.sw == 0x9000 else { throw CardError.pcsc(Int32(r.sw), "Select file") }
        r = try transmit([0x00, 0xB0, 0x00, 0x00, 0x04])
        guard r.sw == 0x9000, r.data.count == 4 else { throw CardError.pcsc(Int32(r.sw), "Read header") }
        let total = 4 + Int(r.data[2]) + Int(r.data[3]) << 8
        var data = r.data
        while data.count < total {
            let n = min(0xE0, total - data.count)
            let o = data.count
            r = try transmit([0x00, 0xB0, UInt8(o >> 8), UInt8(o & 0xFF), UInt8(n)])
            guard r.sw == 0x9000, !r.data.isEmpty else { throw CardError.pcsc(Int32(r.sw), "Read binary") }
            data += r.data
        }
        let d = Data(data)
        rawCache[fid] = d
        return d
    }

    static func parseRecords(_ data: Data) -> [UInt16: Data] {
        let data = Data(data)   // zero-based indices
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

    static func bytes(hex: String) -> [UInt8] {
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

    // MARK: Personal data

    func readPersonalData() throws -> PersonalData {
        var p = PersonalData()
        p.cardType = try selectApplet()
        let doc = try readFile(fid: 0x0F02)
        let fixed = try readFile(fid: 0x0F03)
        let variable = try readFile(fid: 0x0F04)
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
        p.portrait = try readFile(fid: 0x0F06)[0x0110]
        return p
    }

    /// Certificates are stored inside a BER CMS blob; the X.509 DER follows an `A0 80` marker.
    func readCertificates() throws -> [CertificateInfo] {
        try selectApplet()
        var result: [CertificateInfo] = []
        for (fid, tag, type) in [(UInt16(0x0F1C), UInt16(0x0810), EidCertType.sigFixed),
                                 (UInt16(0x0F1D), UInt16(0x0820), EidCertType.sigVariable)] {
            guard let blob = try? readFile(fid: fid)[tag],
                  let der = Self.extractCertificate(from: blob) else { continue }
            result.append(CertificateInfo(type: type, der: der))
        }
        return result
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

    // MARK: Signatures

    /// Card signatures (verified against CelikApi.dll on an RP2024 card):
    /// file 0F1C = CMS SignedData whose content is a list of SHA-256 hashes of whole files
    /// (0F1B, 0F02, 0F03, 0F06, ..., 0FA1, 0FA2); file 0F1D = CMS whose content is SHA-256 of file 0F04.
    /// The CMS signer certificate must chain to a MUP CA bundled in Resources/CA.
    /// Expects the eID applet to be selected (readPersonalData does that).
    func verify(signature: EidSignature) throws -> Bool {
        if signature == .portrait { throw CardError.unsupportedForCard }  // new cards: covered by .fixed
        let (cmsFile, cmsTag, covered): (UInt16, UInt16, [UInt16]) = {
            switch signature {
            case .variable: return (0x0F1D, 0x0820, [0x0F04])
            case .card: return (0x0F1C, 0x0810, [0x0F02])
            default: return (0x0F1C, 0x0810, [0x0F1B, 0x0F02, 0x0F03, 0x0F06, 0x0FA1, 0x0FA2])
            }
        }()
        guard let blob = try readFile(fid: cmsFile)[cmsTag] else {
            throw CardError.signature("signature block missing")
        }
        let content = try SignatureVerifier.verifyCMS(blob)          // throws if sig/chain bad
        for fid in covered {
            let raw = try readRawFile(fid: fid)
            guard SignatureVerifier.sha256(raw).isSubset(of: content) else {
                throw CardError.signature(String(format: "hash mismatch for file %04X", fid))
            }
        }
        return true
    }

    // MARK: Token (PKCS#15 applet A000000063504B43532D3135) — read-only, no PIN needed.
    // Layout observed on a NetSeT CardEdge token (MS minidriver style):
    //   70F3 = label (32 bytes, space padded) + serial; 7102 = user certificate:
    //   [len LE16][01 00][uncompressed size LE16][zlib stream] -> X.509 DER (verified, chain OK);
    //   8007 = [01 71 02 len] + certificate label. File size comes from bytes 2-3 (BE) of the SELECT FCI.
    // Private-key files (6005, 8xxx) and any PIN operation are deliberately NOT touched.

    private func readTokenFile(fid: UInt16) throws -> Data {
        let sel = try transmit([0x00, 0xA4, 0x00, 0x00, 0x02, UInt8(fid >> 8), UInt8(fid & 0xFF)])
        guard sel.sw == 0x9000, sel.data.count >= 4 else { throw CardError.pcsc(Int32(sel.sw), "Select token file") }
        let size = Int(sel.data[2]) << 8 | Int(sel.data[3])
        var out = Data()
        while out.count < size {
            let n = min(0xE0, size - out.count)
            let o = out.count
            let r = try transmit([0x00, 0xB0, UInt8(o >> 8), UInt8(o & 0xFF), UInt8(n)])
            guard r.sw == 0x9000, !r.data.isEmpty else { throw CardError.pcsc(Int32(r.sw), "Read token file") }
            out += r.data
        }
        return out
    }

    private func selectTokenApplet() throws {
        let aid = Self.bytes(hex: Self.tokenAID)
        let r = try transmit([0x00, 0xA4, 0x04, 0x00, UInt8(aid.count)] + aid)
        guard r.sw == 0x9000 else { throw CardError.unsupportedForCard }
    }

    func readToken() throws -> TokenInfo {
        try selectTokenApplet()
        var info = TokenInfo()
        if let d = try? readTokenFile(fid: 0x70F3), d.count > 32 {
            info.tokenLabel = (String(data: d.prefix(32), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespaces)
            info.tokenSerial = (String(data: d.dropFirst(32).prefix { $0 >= 0x20 && $0 < 0x7F }, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespaces)
        }
        if let blob = try? readTokenFile(fid: 0x7102), blob.count > 8,
           let der = TokenCodec.inflate(Data(blob.dropFirst(6))) {
            var label = ""
            if let l = try? readTokenFile(fid: 0x8007), l.count > 4 {
                let len = Int(l[3])
                label = String(data: l[4..<min(l.count, 4 + len)], encoding: .utf8) ?? ""
            }
            info.certificates.append(TokenCertificate(label: label, der: der))
        }
        return info
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

    private func txFollow(_ apdu: [UInt8]) throws -> Response {
        var r = try transmit(apdu)
        var data = r.data
        while r.sw >> 8 == 0x61 {   // T=0 "more data": GET RESPONSE
            r = try transmit([0x00, 0xC0, 0x00, 0x00, UInt8(r.sw & 0xFF)])
            data += r.data
        }
        return (data, r.sw)
    }

    private func verifyPin(_ pin: String) throws {
        let r = try txFollow([0x00, 0x20, 0x00, 0x80, 0x08] + (try Self.paddedPin(pin)))
        if r.sw == 0x9000 { return }
        if r.sw == 0x6983 || r.sw == 0x63C0 { throw CardError.pinBlocked }
        if r.sw >> 4 == 0x063C { throw CardError.pinWrong(triesLeft: Int(r.sw & 0xF)) }
        throw CardError.pcsc(Int32(r.sw), "Verify PIN")
    }

    func changeTokenPin(old: String, new: String) throws {
        let data = try Self.paddedPin(old) + Self.paddedPin(new)
        try selectTokenApplet()
        let r = try txFollow([0x00, 0x24, 0x00, 0x80, 0x10] + data)
        if r.sw == 0x9000 { return }
        if r.sw == 0x6983 || r.sw == 0x63C0 { throw CardError.pinBlocked }
        if r.sw >> 4 == 0x063C { throw CardError.pinWrong(triesLeft: Int(r.sw & 0xF)) }
        throw CardError.pcsc(Int32(r.sw), "Change PIN")
    }

    func tokenSign(pin: String, keyFile: UInt16, digestInfo: Data) throws -> Data {
        guard digestInfo.count <= 255 else { throw CardError.signature("digest too long") }
        try selectTokenApplet()
        try verifyPin(pin)        // single attempt, never retried
        let mse: [UInt8] = [0x80, 0x01, 0x02, 0x84, 0x02, UInt8(keyFile >> 8), UInt8(keyFile & 0xFF)]
        var r = try txFollow([0x00, 0x22, 0x41, 0xB6, UInt8(mse.count)] + mse)
        guard r.sw == 0x9000 else { throw CardError.pcsc(Int32(r.sw), "MSE SET") }
        r = try txFollow([0x00, 0x2A, 0x9E, 0x00, UInt8(digestInfo.count)] + [UInt8](digestInfo) + [0x00])
        guard r.sw == 0x9000, !r.data.isEmpty else { throw CardError.pcsc(Int32(r.sw), "Sign") }
        return Data(r.data)
    }
}
