import Foundation

// Health insurance card (KZO, RFZO): data model, block parser, rows for the screen and the reader.
// STATUS: written from the analysis of the official RFZO reader and its middleware (docs/health-card-protocol.md).
// Confirmed by that analysis ONLY, NOT yet against a real card. The tag <-> name assignment is inferred from the declaration
// order and the field sizes. Same logic as windows/SerbiaID.Windows/HealthData.cs and HealthCard.cs and the Kotlin port.

struct HealthData {
    // block 0D01 document
    var insurerName = "", insurerId = "", cardId = "", issueDate = "", expiryDate = "", chipSerial = "", printLanguage = ""
    // block 0D02 fixed personal
    var insurantNumber = "", surname = "", surnameLatin = "", givenName = "", givenNameLatin = "", dateOfBirth = ""
    // block 0D03 card validity
    var permanent = false
    // block 0D04 administrative
    var parentName = "", parentNameLatin = "", gender = "", personalNumber = ""
    var street = "", postNumber = "", municipality = "", place = "", streetCode = "", houseNumber = "", entrance = "", apartment = ""
    var registrationNumber = "", basisCode = "", basisDescription = ""
    var carrierRelationship = "", carrierFamilyMember = "", carrierPersonalNumber = "", carrierInsurantNumber = ""
    var carrierSurname = "", carrierSurnameLatin = "", carrierGivenName = "", carrierGivenNameLatin = ""
    var insuredFrom = "", countryCode = "", country = "", bookletIssuerCode = "", insurerBranch = "", insurerOffice = ""
    var taxpayerName = "", taxpayerResidence = "", taxpayerNumber = "", taxpayerIdNumber = "", taxpayerActivityCode = "", participationFree = ""

    /// Blocks that could not be read, and tags the table does not know (structure only, no values).
    var problems: [String] = []
    var unknownTags: [String] = []

    var fullName: String { "\(givenName) \(surname)".trimmingCharacters(in: .whitespaces) }
    var carrierFullName: String { "\(carrierGivenName) \(carrierSurname)".trimmingCharacters(in: .whitespaces) }
}

enum HealthParser {
    static let document: UInt16 = 0x0D01, fixed: UInt16 = 0x0D02, card: UInt16 = 0x0D03, admin: UInt16 = 0x0D04

    private enum Kind { case ascii, utf16, date, number }

    private static let kinds: [Int: Kind] = [
        0x611: .utf16, 0x612: .ascii, 0x613: .ascii, 0x615: .date, 0x616: .date, 0x617: .ascii, 0x618: .ascii,
        0x621: .ascii, 0x622: .utf16, 0x623: .utf16, 0x624: .utf16, 0x625: .utf16, 0x626: .date,
        0x630: .ascii, 0x631: .date, 0x632: .date, 0x633: .number,
        0x640: .ascii, 0x641: .utf16, 0x642: .utf16, 0x643: .number, 0x644: .ascii, 0x645: .utf16, 0x646: .ascii, 0x647: .utf16, 0x648: .utf16,
        0x649: .ascii, 0x64A: .utf16, 0x64B: .utf16, 0x64C: .utf16, 0x64D: .ascii, 0x64E: .ascii, 0x64F: .utf16, 0x650: .utf16, 0x651: .number,
        0x652: .ascii, 0x653: .ascii, 0x654: .utf16, 0x655: .utf16, 0x656: .utf16, 0x657: .utf16, 0x658: .date, 0x659: .ascii, 0x65A: .utf16,
        0x65B: .ascii, 0x65C: .utf16, 0x65D: .utf16, 0x65E: .utf16, 0x65F: .utf16, 0x660: .ascii, 0x661: .ascii, 0x662: .ascii, 0x663: .ascii,
    ]

    /// The elements of a block file: header [id LE16][length LE16], then [tag LE16][length LE16][value]...
    /// nil if the header does not match `expectedId` or the declared length is more than the file holds.
    static func records(_ file: [UInt8]?, expectedId: UInt16) -> [Int: [UInt8]]? {
        guard let f = file, f.count >= 4 else { return nil }
        guard Int(f[0]) | Int(f[1]) << 8 == Int(expectedId) else { return nil }
        let declared = Int(f[2]) | Int(f[3]) << 8
        guard declared <= f.count - 4 else { return nil }
        var d: [Int: [UInt8]] = [:]
        var p = 4; let end = 4 + declared
        while p + 4 <= end {
            let tag = Int(f[p]) | Int(f[p + 1]) << 8, len = Int(f[p + 2]) | Int(f[p + 3]) << 8
            if p + 4 + len > end { break }
            d[tag] = Array(f[(p + 4)..<(p + 4 + len)])
            p += 4 + len
        }
        return d
    }

    static func value(_ d: [Int: [UInt8]], _ tag: Int) -> String {
        guard let b = d[tag], !b.isEmpty else { return "" }
        let kind = kinds[tag] ?? .ascii
        if kind == .number {
            var n: UInt64 = 0
            for x in b.prefix(8).reversed() { n = n << 8 | UInt64(x) }
            return String(n)
        }
        var s: String
        // UTF-16LE needs an even length; if a card hands odd bytes, read them as UTF-8 rather than lose the text
        if kind == .utf16 && b.count % 2 == 0 { s = String(data: Data(b), encoding: .utf16LittleEndian) ?? "" }
        else { s = String(decoding: b, as: UTF8.self) }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        return kind == .date ? date(s) : s
    }

    /// The card stores DDMMYYYY; shown as DD.MM.YYYY like the ID card.
    static func date(_ s: String) -> String {
        let c = Array(s)
        guard c.count == 8, c.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return s }
        return String(c[0..<2]) + "." + String(c[2..<4]) + "." + String(c[4...])
    }

    /// Builds the data from the four block files (nil = block not read). Never throws on content.
    static func parse(document doc: [UInt8]?, fixed fix: [UInt8]?, card cardFile: [UInt8]?, admin adminFile: [UInt8]?) -> HealthData {
        var h = HealthData()
        var rec: [UInt16: [Int: [UInt8]]] = [:]
        for (id, f) in [(document, doc), (fixed, fix), (card, cardFile), (admin, adminFile)] {
            let name = String(format: "%04X", id)
            guard let file = f else { h.problems.append(name + ": not read"); continue }
            guard let r = records(file, expectedId: id) else { h.problems.append(name + ": bad header"); continue }
            rec[id] = r
            for t in r.keys.sorted() where kinds[t] == nil { h.unknownTags.append(name + "/" + String(format: "%03X", t) + "/\(r[t]!.count)") }
        }
        if let d = rec[document] {
            h.insurerName = value(d, 0x611); h.insurerId = value(d, 0x612); h.cardId = value(d, 0x613)
            h.issueDate = value(d, 0x615); h.expiryDate = value(d, 0x616); h.chipSerial = value(d, 0x617); h.printLanguage = value(d, 0x618)
        }
        if let d = rec[fixed] {
            h.insurantNumber = value(d, 0x621); h.surname = value(d, 0x622); h.surnameLatin = value(d, 0x623)
            h.givenName = value(d, 0x624); h.givenNameLatin = value(d, 0x625); h.dateOfBirth = value(d, 0x626)
        }
        if let d = rec[card] {
            if h.cardId.isEmpty { h.cardId = value(d, 0x630) }
            if h.issueDate.isEmpty { h.issueDate = value(d, 0x631) }
            let exp = value(d, 0x632)
            if !exp.isEmpty { h.expiryDate = exp }     // the validity block is the one that changes when the card is renewed
            h.permanent = value(d, 0x633) == "1"
        }
        if let d = rec[admin] {
            h.parentName = value(d, 0x641); h.parentNameLatin = value(d, 0x642)
            let g = value(d, 0x643); h.gender = g == "1" ? "M" : g == "2" ? "Ž" : g
            h.personalNumber = value(d, 0x644); h.street = value(d, 0x645); h.postNumber = value(d, 0x646)
            h.municipality = value(d, 0x647); h.place = value(d, 0x648); h.streetCode = value(d, 0x649)
            h.houseNumber = value(d, 0x64A); h.entrance = value(d, 0x64B); h.apartment = value(d, 0x64C)
            h.registrationNumber = value(d, 0x64D); h.basisCode = value(d, 0x64E); h.basisDescription = value(d, 0x64F)
            h.carrierRelationship = value(d, 0x650); h.carrierFamilyMember = value(d, 0x651)
            h.carrierPersonalNumber = value(d, 0x652); h.carrierInsurantNumber = value(d, 0x653)
            h.carrierSurname = value(d, 0x654); h.carrierSurnameLatin = value(d, 0x655)
            h.carrierGivenName = value(d, 0x656); h.carrierGivenNameLatin = value(d, 0x657)
            h.insuredFrom = value(d, 0x658); h.countryCode = value(d, 0x659); h.country = value(d, 0x65A)
            h.bookletIssuerCode = value(d, 0x65B); h.insurerBranch = value(d, 0x65C); h.insurerOffice = value(d, 0x65D)
            h.taxpayerName = value(d, 0x65E); h.taxpayerResidence = value(d, 0x65F); h.taxpayerNumber = value(d, 0x660)
            h.taxpayerIdNumber = value(d, 0x661); h.taxpayerActivityCode = value(d, 0x662); h.participationFree = value(d, 0x663)
        }
        return h
    }
}

enum HealthRows {
    /// Hidden behind the eye like the ID card's personal number and address (keys are Loc.x keys).
    static let sensitive: Set<String> = ["hLbo", "hJmbg", "hAddress", "hCardId", "hRfzoNo", "hCarrierName", "hCarrierLbo", "hCarrierJmbg", "hTaxPib", "hTaxId"]

    static func address(_ h: HealthData) -> String {
        var parts = ["\(h.street) \(h.houseNumber)".trimmingCharacters(in: .whitespaces)]
        if !h.entrance.isEmpty { parts.append("ul. " + h.entrance) }
        if !h.apartment.isEmpty { parts.append("stan " + h.apartment) }
        parts.append("\(h.postNumber) \(h.place)".trimmingCharacters(in: .whitespaces))
        parts.append(h.municipality); parts.append(h.country)
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The insured person, the card, the insurance, the holder and the payer when present.
    static func sections(_ h: HealthData, includeJmbg: Bool = true) -> [(title: String, rows: [(key: String, value: String)])] {
        func g(_ kv: [(String, String)]) -> [(key: String, value: String)] { kv.filter { !$0.1.isEmpty }.map { (key: $0.0, value: $0.1) } }
        let person = g([("hSurname", h.surname), ("hGivenName", h.givenName), ("hParent", h.parentName), ("hDob", h.dateOfBirth), ("hSex", h.gender),
                        ("hJmbg", includeJmbg ? h.personalNumber : ""), ("hLbo", h.insurantNumber), ("hAddress", address(h))])
        let card = g([("hInsurer", h.insurerName), ("hCardId", h.cardId), ("hIssued", h.issueDate),
                      ("hValidUntil", h.permanent ? "" : h.expiryDate), ("hPermanent", h.permanent ? "✔" : ""), ("hIssuerCode", h.bookletIssuerCode)])
        let ins = g([("hBasis", [h.basisCode, h.basisDescription].filter { !$0.isEmpty }.joined(separator: " — ")),
                     ("hInsuredFrom", h.insuredFrom), ("hBranch", h.insurerBranch), ("hOffice", h.insurerOffice),
                     ("hRfzoNo", h.registrationNumber), ("hExempt", h.participationFree)])
        let carrier = g([("hCarrierName", h.carrierFullName), ("hCarrierLbo", h.carrierInsurantNumber),
                         ("hCarrierJmbg", includeJmbg ? h.carrierPersonalNumber : ""), ("hRelation", h.carrierRelationship), ("hFamilyMember", h.carrierFamilyMember)])
        let tax = g([("hTaxName", h.taxpayerName), ("hTaxResidence", h.taxpayerResidence), ("hTaxPib", h.taxpayerNumber),
                     ("hTaxId", h.taxpayerIdNumber), ("hTaxActivity", h.taxpayerActivityCode)])
        return [("hSecPerson", person), ("hSecCard", card), ("hSecInsurance", ins), ("hSecCarrier", carrier), ("hSecTaxpayer", tax)]
    }

    static func build(_ h: HealthData, includeJmbg: Bool = true) -> [(key: String, value: String)] {
        sections(h, includeJmbg: includeJmbg).flatMap { $0.rows }
    }

    /// Fictional data for demo mode, screenshots and the tests.
    static func demo() -> HealthData {
        var h = HealthData()
        h.insurerName = "REPUBLIČKI FOND ZA ZDRAVSTVENO OSIGURANJE"; h.insurerId = "100000000"; h.cardId = "00000000001"
        h.issueDate = "01.01.2024"; h.expiryDate = "01.01.2029"; h.chipSerial = "0000000000000000"; h.printLanguage = "sr"
        h.insurantNumber = "00000000001"; h.surname = "PETROVIĆ"; h.surnameLatin = "PETROVIC"; h.givenName = "MARKO"; h.givenNameLatin = "MARKO"
        h.dateOfBirth = "01.01.1990"; h.parentName = "JOVAN"; h.parentNameLatin = "JOVAN"; h.gender = "M"; h.personalNumber = "0101990710000"
        h.street = "Knez Mihailova"; h.houseNumber = "1"; h.postNumber = "11000"; h.place = "Beograd"; h.municipality = "Stari Grad"
        h.country = "Srbija"; h.countryCode = "688"; h.registrationNumber = "0000000001"; h.basisCode = "010"; h.basisDescription = "Zaposleni"
        h.insuredFrom = "01.01.2015"; h.insurerBranch = "Filijala za grad Beograd"; h.insurerOffice = "Ispostava Stari Grad"; h.bookletIssuerCode = "001"
        h.taxpayerName = "PRIMER D.O.O."; h.taxpayerResidence = "Beograd"; h.taxpayerNumber = "100000000"; h.taxpayerIdNumber = "0000000000000"; h.taxpayerActivityCode = "6201"
        return h
    }
}

/// Reads the health card through any APDU channel (PC/SC on the Mac, USB reader on iOS).
final class HealthCard {
    typealias Response = (data: [UInt8], sw: UInt16)
    private let transmit: ([UInt8]) throws -> Response
    init(transmit: @escaping ([UInt8]) throws -> Response) { self.transmit = transmit }

    /// "F381000002" + "SERVSZK" + 01 (card type 1, the one the official reader asks for) and the second type's name ("SERSOVOZK").
    static let aids = ["F38100000253455256535A4B01", "F381000002534552534F564F5A4B01"]
    static let blocks: [UInt16] = [HealthParser.document, HealthParser.fixed, HealthParser.card, HealthParser.admin]

    private static func apdu(_ ins: UInt8, _ p1: UInt8, _ p2: UInt8, _ data: [UInt8] = [], le: UInt8? = nil) -> [UInt8] {
        var a: [UInt8] = [0x00, ins, p1, p2]
        if !data.isEmpty { a.append(UInt8(data.count)); a += data }
        if let le { a.append(le) }
        return a
    }

    /// Like transmit, but follows T=0 "61xx" (GET RESPONSE).
    private func tx(_ apdu: [UInt8]) throws -> Response {
        var r = try transmit(apdu)
        var data = r.data
        while r.sw >> 8 == 0x61 {
            r = try transmit([0x00, 0xC0, 0x00, 0x00, UInt8(r.sw & 0xFF)])
            data += r.data
        }
        return (data, r.sw)
    }

    /// Selects the applet of a health card; returns its AID, or nil if the card has none of them.
    func selectApplet() throws -> String? {
        for aid in Self.aids {
            let r = try transmit(Self.apdu(0xA4, 0x04, 0x00, RegistrationCard.bytes(hex: aid)))
            if r.sw == 0x9000 || r.sw >> 8 == 0x61 { return aid }
        }
        return nil
    }

    /// One block: select the applet, select the file (00 A4 00 00 02 <id>), read the 4-byte header, then the rest in chunks of 0x80.
    func readBlock(aid: String, id: UInt16) throws -> [UInt8] {
        let sel = try tx(Self.apdu(0xA4, 0x04, 0x00, RegistrationCard.bytes(hex: aid)))
        guard sel.sw == 0x9000 else { throw CardError.pcsc(Int32(sel.sw), "Select applet") }
        let fid = [UInt8(id >> 8), UInt8(id & 0xFF)]
        var r = try tx(Self.apdu(0xA4, 0x00, 0x00, fid))
        if r.sw != 0x9000 { r = try tx(Self.apdu(0xA4, 0x00, 0x0C, fid)) }    // some cards answer only to the "no response" form
        guard r.sw == 0x9000 else { throw CardError.pcsc(Int32(r.sw), "Select file") }
        let fileSize = r.data.count >= 4 ? Int(r.data[2]) << 8 | Int(r.data[3]) : 0   // bytes 2-3, big-endian, when the card returns them
        guard !(fileSize > 0 && fileSize < 4) else { throw CardError.pcsc(0x6700, "File too small") }

        r = try transmit(Self.apdu(0xB0, 0x00, 0x00, le: 4))
        guard r.sw == 0x9000, r.data.count == 4 else { throw CardError.pcsc(Int32(r.sw), "Read header") }
        guard Int(r.data[0]) | Int(r.data[1]) << 8 == Int(id) else { throw CardError.pcsc(0x6A82, "Other block") }
        let total = 4 + (Int(r.data[2]) | Int(r.data[3]) << 8)
        guard total <= 16384, !(fileSize > 0 && total > fileSize) else { throw CardError.pcsc(0x6700, "Bad length") }
        var data = r.data
        while data.count < total {
            let o = data.count, n = min(0x80, total - o)
            r = try transmit(Self.apdu(0xB0, UInt8(o >> 8), UInt8(o & 0xFF), le: UInt8(n)))
            guard r.sw == 0x9000, !r.data.isEmpty else { throw CardError.pcsc(Int32(r.sw), "Read binary") }
            data += r.data
        }
        return data
    }

    func read() throws -> HealthData {
        guard let aid = try selectApplet() else { throw CardError.unsupportedForCard }
        var files: [[UInt8]?] = []
        var problems: [String] = []
        for id in Self.blocks {
            do { files.append(try readBlock(aid: aid, id: id)) }
            catch { files.append(nil); problems.append(String(format: "%04X: ", id) + error.localizedDescription) }
        }
        // the names are the minimum: without the fixed personal block there is nothing worth showing
        guard files[1] != nil else { throw CardError.unsupportedForCard }
        var h = HealthParser.parse(document: files[0], fixed: files[1], card: files[2], admin: files[3])
        h.problems += problems
        return h
    }
}
