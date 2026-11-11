import Foundation
import CPCSC

// Data model: CardModel.swift. Card protocol (shared with iOS): EidCard.swift.

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
    /// Unblock with PUK + set a new PIN (APDU unverified; one attempt only).
    func unblockTokenPin(reader: String, puk: String, new: String) throws
    /// RSA PKCS#1 v1.5 signature over `digestInfo` (DER DigestInfo = hash OID + hash).
    func tokenSign(reader: String, pin: String, keyFile: UInt16, digestInfo: Data) throws -> Data
    /// Per the official API this works only on the old (Apollo) card, 5...16 chars, ISO-8859-1.
    func changePin(reader: String, cardType: EidCardType, old: String, new: String) throws -> Int
}

// MARK: - PC/SC implementation (macOS). The card protocol itself lives in EidCard.swift.

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

    /// Connects to the card and hands the shared protocol code an APDU channel to it.
    private func withEid<T>(reader: String, _ body: (EidCard) throws -> T) throws -> T {
        try withCard(reader: reader) { card, proto in
            try body(EidCard { apdu in try self.transmit(card: card, proto: proto, apdu: apdu) })
        }
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

    func readPersonalData(reader: String) throws -> PersonalData {
        try withEid(reader: reader) { try $0.readPersonalData() }
    }

    func readCertificates(reader: String, cardType: EidCardType) throws -> [CertificateInfo] {
        try withEid(reader: reader) { try $0.readCertificates() }
    }

    func readToken(reader: String) throws -> TokenInfo {
        try withEid(reader: reader) { try $0.readToken() }
    }

    func changeTokenPin(reader: String, old: String, new: String) throws {
        try withEid(reader: reader) { try $0.changeTokenPin(old: old, new: new) }
    }

    func unblockTokenPin(reader: String, puk: String, new: String) throws {
        try withEid(reader: reader) { try $0.unblockTokenPin(puk: puk, new: new) }
    }

    func tokenSign(reader: String, pin: String, keyFile: UInt16, digestInfo: Data) throws -> Data {
        try withEid(reader: reader) { try $0.tokenSign(pin: pin, keyFile: keyFile, digestInfo: digestInfo) }
    }

    func verify(reader: String, signature: EidSignature) throws -> Bool {
        if signature == .portrait { throw CardError.unsupportedForCard }  // new cards: covered by .fixed
        return try withEid(reader: reader) { card in
            try card.selectApplet()
            return try card.verify(signature: signature)
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
    func unblockTokenPin(reader: String, puk: String, new: String) throws {}
    func tokenSign(reader: String, pin: String, keyFile: UInt16, digestInfo: Data) throws -> Data { Data(count: 256) }
}

