import Foundation

// Vehicle registration card (Saobraćajna dozvola), shared by the macOS and iOS apps.
// Parsing is written from the EU directive 1999/37/EC as amended by 2003/127/EC (Annex I, chapter III) and from the
// MUP RS "eVehicle Registration SDK" field table; see docs/cards-research.md.
// STATUS: confirmed against the specification only, NOT yet against a real card.

// MARK: - BER-TLV (ISO/IEC 7816-4)

struct Tlv {
    var tag: Int
    var constructed: Bool
    var value: [UInt8]
    var children: [Tlv] = []

    var tagHex: String {
        let s = String(tag, radix: 16, uppercase: true)
        return s.count % 2 == 1 ? "0" + s : s
    }
}

enum Ber {
    /// Parses a run of TLV objects; trailing zero padding is ignored. nil = not well-formed BER.
    static func parse(_ d: [UInt8]) -> [Tlv]? { parse(d, 0, d.count, 0) }

    private static func parse(_ d: [UInt8], _ start: Int, _ end: Int, _ depth: Int) -> [Tlv]? {
        var pos = start
        var list: [Tlv] = []
        if depth > 8 { return nil }
        while pos < end {
            if d[pos] == 0x00 || d[pos] == 0xFF {                        // padding
                let pad = d[pos]
                for i in pos..<end where d[i] != pad { return nil }
                break
            }
            let b0 = Int(d[pos]); pos += 1
            var tag = b0
            if b0 & 0x1F == 0x1F {
                var n = 0
                repeat {
                    n += 1
                    if pos >= end || n > 2 { return nil }
                    tag = tag << 8 | Int(d[pos])
                    pos += 1
                } while d[pos - 1] & 0x80 != 0
            }
            if pos >= end { return nil }
            var len = Int(d[pos]); pos += 1
            if len >= 0x80 {
                let n = len & 0x7F
                if n < 1 || n > 3 || pos + n > end { return nil }
                len = 0
                for _ in 0..<n { len = len << 8 | Int(d[pos]); pos += 1 }
            }
            if pos + len > end { return nil }
            var t = Tlv(tag: tag, constructed: b0 & 0x20 != 0, value: Array(d[pos..<pos + len]))
            if t.constructed {
                guard let kids = parse(d, pos, pos + len, depth + 1) else { return nil }
                t.children = kids
            } else if tag == 0x5A && len > 2 {
                // The MUP SDK table nests the engine data under '5A', a primitive tag by the BER rules.
                // If the value is a well-formed run of TLVs, treat it as constructed (unconfirmed, see docs).
                if let inner = parse(d, pos, pos + len, depth + 1), !inner.isEmpty { t.constructed = true; t.children = inner }
            }
            list.append(t)
            pos += len
        }
        return list
    }

    static func build(_ tag: Int, _ value: [UInt8]) -> [UInt8] {
        var o: [UInt8] = []
        if tag > 0xFFFF { o.append(UInt8(tag >> 16 & 0xFF)) }
        if tag > 0xFF { o.append(UInt8(tag >> 8 & 0xFF)) }
        o.append(UInt8(tag & 0xFF))
        if value.count < 0x80 { o.append(UInt8(value.count)) }
        else if value.count < 0x100 { o += [0x81, UInt8(value.count)] }
        else { o += [0x82, UInt8(value.count >> 8), UInt8(value.count & 0xFF)] }
        return o + value
    }
}

// MARK: - Data

struct VehicleData {
    // document
    var stateIssuing = "", competentAuthority = "", authorityIssuing = "", unambiguousNumber = ""
    var issuingDate = "", expiryDate = "", serialNumber = ""
    // vehicle
    var registrationNumber = "", firstRegistrationDate = "", yearOfProduction = "", make = "", type = ""
    var commercialDescription = "", vin = "", maxNetPower = "", engineCapacity = "", fuelType = ""
    var powerWeightRatio = "", mass = "", maxLadenMass = "", typeApprovalNumber = "", seats = "", standingPlaces = ""
    var engineNumber = "", axles = "", category = "", colour = "", saleBan = "", load = ""
    // owner and user
    var ownerPersonalNo = "", ownerSurname = "", ownerName = "", ownerAddress = ""
    var userPersonalNo = "", userSurname = "", userName = "", userAddress = ""
    /// Character set tag 9F37 as read (-1 = absent).
    var charsetTag = -1
    /// Structure of what was not recognised (path/length), no values.
    var unknownTags: [String] = []
    /// true only after the issuer signature has been checked (not implemented: algorithm unknown, see docs).
    var signatureVerified = false

    var ownerFull: String { (ownerName + " " + ownerSurname).trimmingCharacters(in: .whitespaces) }
    var userFull: String { (userName + " " + userSurname).trimmingCharacters(in: .whitespaces) }
}

enum VehicleParser {
    /// Parses the content of the registration data files (D001, D011, D021 and the unsigned national file, in any order).
    static func parse(_ files: [[UInt8]]) -> VehicleData {
        var v = VehicleData()
        let trees = files.compactMap { f -> [Tlv]? in
            guard let t = Ber.parse(f), !t.isEmpty else { return nil }
            return t
        }
        for t in trees { findCharset(t, &v) }
        var holder: [String?] = [nil, nil, nil]   // A2 (holder in part 1): the owner only if there is no A7
        for t in trees { walk(t, "", &v, &holder) }
        if v.ownerSurname.isEmpty && v.ownerName.isEmpty && v.ownerAddress.isEmpty {
            v.ownerSurname = holder[0] ?? ""; v.ownerName = holder[1] ?? ""; v.ownerAddress = holder[2] ?? ""
        }
        return v
    }

    private static func findCharset(_ nodes: [Tlv], _ v: inout VehicleData) {
        for n in nodes {
            if n.tag == 0x9F37, let f = n.value.first, v.charsetTag < 0 { v.charsetTag = Int(f) }
            if n.constructed { findCharset(n.children, &v) }
        }
    }

    private static func walk(_ nodes: [Tlv], _ path: String, _ v: inout VehicleData, _ holder: inout [String?]) {
        for n in nodes {
            let key = path.isEmpty ? n.tagHex : path + "." + n.tagHex
            if path.isEmpty && [0x71, 0x72, 0x73, 0x74].contains(n.tag) { walk(n.children, "", &v, &holder); continue }
            if n.constructed { walk(n.children, key, &v, &holder); continue }
            assign(&v, key, CardText.decode(n.value, charset: v.charsetTag), n.value.count, &holder)
        }
    }

    private static func assign(_ v: inout VehicleData, _ key: String, _ s: String, _ len: Int, _ holder: inout [String?]) {
        switch key {
        case "78.4F", "80", "9F34", "9F37", "A1.A2.86": break
        case "9F33": v.stateIssuing = s
        case "9F35": v.competentAuthority = s
        case "9F36": v.authorityIssuing = s
        case "9F38": v.unambiguousNumber = s
        case "81": v.registrationNumber = s
        case "82": v.firstRegistrationDate = CardText.date(s)
        case "8D": v.expiryDate = CardText.date(s)
        case "8E": v.issuingDate = CardText.date(s)
        case "8A": v.vin = s
        case "8C": v.mass = s
        case "8F": v.typeApprovalNumber = s
        case "93": v.powerWeightRatio = s
        case "98": v.category = s
        case "99": v.axles = s
        case "9F24": v.colour = s
        case "A3.87": v.make = s
        case "A3.88": v.type = s
        case "A3.89": v.commercialDescription = s
        case "A4.8B", "A4.96": v.maxLadenMass = s
        // the directive nests the engine under A5, the MUP SDK table writes 5A: accept both
        case "A5.90", "5A.90": v.engineCapacity = s
        case "A5.91", "5A.91": v.maxNetPower = s
        case "A5.92", "5A.92": v.fuelType = s
        case "A5.9E", "5A.9E": v.engineNumber = s
        case "A6.94": v.seats = s
        case "A6.95": v.standingPlaces = s
        case "A1.A2.83": holder[0] = s
        case "A1.A2.84": holder[1] = s
        case "A1.A2.85": holder[2] = s
        case "A1.A7.83": v.ownerSurname = s
        case "A1.A7.84": v.ownerName = s
        case "A1.A7.85": v.ownerAddress = s
        case "A1.A9.83": v.userSurname = s
        case "A1.A9.84": v.userName = s
        case "A1.A9.85": v.userAddress = s
        // Serbian extension tags (MUP SDK table)
        case "C1": v.saleBan = s
        case "C2": v.ownerPersonalNo = s
        case "C3": v.userPersonalNo = s
        case "C4": v.load = s
        case "C5": v.yearOfProduction = s
        case "C9": v.serialNumber = s
        default: v.unknownTags.append("\(key)/\(len)")
        }
    }
}

/// Text decoding for card values: ASCII with ISO 8859-1 / -5 / -7 above 0xBF, chosen by tag 9F37 (directive III.11).
enum CardText {
    static func decode(_ b: [UInt8], charset: Int) -> String {
        var end = b.count
        while end > 0 && (b[end - 1] == 0 || b[end - 1] == 0x20) { end -= 1 }
        var start = 0
        while start < end && b[start] == 0x20 { start += 1 }
        let body = Array(b[start..<end])
        // Not in the spec: bytes that are valid UTF-8 with multi-byte characters are taken as UTF-8 (a national
        // deviation would look like this). Which one the cards use is to be seen in the diagnostic log.
        if body.contains(where: { $0 >= 0x80 }), let u = String(bytes: body, encoding: .utf8) { return u }
        return String(String.UnicodeScalarView(body.map { map($0, charset) }))
    }

    private static func map(_ x: UInt8, _ cs: Int) -> Unicode.Scalar {
        let v = Int(x)
        func sc(_ n: Int) -> Unicode.Scalar { Unicode.Scalar(UInt32(n)) ?? "?" }
        if v < 0xA0 { return sc(v) }
        if cs == 1 {                                  // ISO 8859-5 (Cyrillic)
            if v == 0xA0 || v == 0xAD { return sc(v) }
            if v == 0xF0 { return sc(0x2116) }
            if v == 0xFD { return sc(0xA7) }
            return sc(0x0400 + (v - 0xA0))
        }
        if cs == 2 {                                  // ISO 8859-7 (Greek), letters only
            if (0xC1...0xD1).contains(v) { return sc(0x0391 + (v - 0xC1)) }
            if (0xD3...0xD9).contains(v) { return sc(0x03A3 + (v - 0xD3)) }
            if (0xE1...0xF9).contains(v) { return sc(0x03B1 + (v - 0xE1)) }
        }
        return sc(v)                                  // ISO 8859-1
    }

    /// The card stores YYYYMMDD (directive III.11); shown as DD.MM.YYYY like the ID card.
    static func date(_ s: String) -> String {
        let c = Array(s)
        guard c.count == 8, c.allSatisfy({ $0.isASCII && $0.isNumber }) else { return s }
        return String(c[6...7]) + "." + String(c[4...5]) + "." + String(c[0...3])
    }
}

// MARK: - Rows shown by the apps

enum VehicleRows {
    /// Hidden behind the eye like the ID card's personal number and address (keys are Loc.x keys).
    static let sensitive: Set<String> = ["vOwner", "vOwnerAddr", "vOwnerJmbg", "vUser", "vUserAddr", "vUserJmbg", "vDocSerial", "vDocNo", "vSaleBan"]

    static func build(_ v: VehicleData, includeJmbg: Bool = true) -> [(key: String, value: String)] {
        var r: [(key: String, value: String)] = []
        func a(_ k: String, _ s: String) { if !s.isEmpty { r.append((k, s)) } }
        a("vRegNo", v.registrationNumber); a("vMake", v.make); a("vType", v.type); a("vModel", v.commercialDescription)
        a("vVin", v.vin); a("vYear", v.yearOfProduction); a("vColour", v.colour); a("vCategory", v.category)
        a("vFirstReg", v.firstRegistrationDate); a("vValidUntil", v.expiryDate); a("vIssued", v.issuingDate)
        a("vFuel", v.fuelType); a("vCapacity", v.engineCapacity); a("vPower", v.maxNetPower); a("vPowerWeight", v.powerWeightRatio)
        a("vEngineNo", v.engineNumber); a("vMass", v.mass); a("vMaxMass", v.maxLadenMass); a("vLoad", v.load)
        a("vSeats", v.seats); a("vStanding", v.standingPlaces); a("vAxles", v.axles); a("vApproval", v.typeApprovalNumber)
        a("vOwner", v.ownerFull); a("vOwnerAddr", v.ownerAddress); if includeJmbg { a("vOwnerJmbg", v.ownerPersonalNo) }
        a("vUser", v.userFull); a("vUserAddr", v.userAddress); if includeJmbg { a("vUserJmbg", v.userPersonalNo) }
        a("vSaleBan", CardText.date(v.saleBan))
        a("vDocNo", v.unambiguousNumber); a("vDocSerial", v.serialNumber); a("vAuthority", v.authorityIssuing)
        return r
    }

    /// Fictional data for demo mode and screenshots.
    static func demo() -> VehicleData {
        var v = VehicleData()
        v.registrationNumber = "BG 123-AB"; v.make = "ZASTAVA"; v.type = "103"; v.commercialDescription = "YUGO 55"
        v.vin = "VX1146A0000000001"; v.yearOfProduction = "1989"; v.colour = "CRVENA"; v.category = "M1"
        v.firstRegistrationDate = "12.03.1989"; v.expiryDate = "12.03.2027"; v.issuingDate = "12.03.2026"
        v.fuelType = "BENZIN"; v.engineCapacity = "1116"; v.maxNetPower = "41"; v.engineNumber = "0000001"
        v.mass = "790"; v.maxLadenMass = "1215"; v.seats = "5"; v.standingPlaces = "0"; v.axles = "2"
        v.typeApprovalNumber = "e1*00/00*0000"
        v.ownerSurname = "PETROVIĆ"; v.ownerName = "MARKO"; v.ownerAddress = "Knez Mihailova 1, Beograd"; v.ownerPersonalNo = "0101990710000"
        v.unambiguousNumber = "000000001"; v.serialNumber = "SD0000001"; v.authorityIssuing = "PU ZA GRAD BEOGRAD, MINISTARSTVO UNUTRASNJIH POSLOVA REPUBLIKE SRBIJE"
        v.stateIssuing = "REPUBLIKA SRBIJA"; v.load = "0"; v.powerWeightRatio = "0"
        return v
    }
}

// MARK: - Reading over any APDU channel

/// Reads the registration card through an APDU channel (PC/SC on the Mac, USB reader on iOS).
/// The application name is NOT published; the candidates come from analysing MUP's own SDK binary and are unconfirmed.
final class RegistrationCard {
    typealias Response = (data: [UInt8], sw: UInt16)
    private let transmit: ([UInt8]) throws -> Response
    init(transmit: @escaping ([UInt8]) throws -> Response) { self.transmit = transmit }

    /// Candidate application names, in this order: the ID-card scheme F381000002 + "SERVL" + 01 by analogy,
    /// the same as a prefix (ISO 7816-4 allows partial DF names with P2=00), and a longer form seen in the SDK.
    static let candidateAids = ["F381000002534552564C01", "F381000002534552564C", "F381000002534552564C040201"]
    static let dataFiles: [UInt16] = [0xD001, 0xD011, 0xD021]

    static func bytes(hex: String) -> [UInt8] {
        var out: [UInt8] = []; var i = hex.startIndex
        while i < hex.endIndex { let j = hex.index(i, offsetBy: 2); out.append(UInt8(hex[i..<j], radix: 16) ?? 0); i = j }
        return out
    }

    static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined() }

    static func apdu(_ ins: UInt8, _ p1: UInt8, _ p2: UInt8, _ data: [UInt8] = [], le: UInt8? = nil) -> [UInt8] {
        var a: [UInt8] = [0x00, ins, p1, p2]
        if !data.isEmpty { a.append(UInt8(data.count)); a += data }
        if let le { a.append(le) }
        return a
    }

    /// One APDU as it is, for the diagnostics.
    func rawTransmit(_ apdu: [UInt8]) throws -> Response { try transmit(apdu) }

    /// Like transmit, but follows T=0 "61xx" (GET RESPONSE).
    func tx(_ apdu: [UInt8]) throws -> Response {
        var r = try transmit(apdu)
        var data = r.data
        while r.sw >> 8 == 0x61 {
            r = try transmit([0x00, 0xC0, 0x00, 0x00, UInt8(r.sw & 0xFF)])
            data += r.data
        }
        return (data, r.sw)
    }

    func selectApplication() throws -> String? {
        for aid in Self.candidateAids {
            let r = try transmit(Self.apdu(0xA4, 0x04, 0x00, Self.bytes(hex: aid)))
            if r.sw == 0x9000 || r.sw >> 8 == 0x61 { return aid }
        }
        return nil
    }

    /// File size from the FCP/FCI: tag 80 or 81 (also inside 62 / 6F). 0 = not given.
    static func fcpSize(_ fcp: [UInt8]) -> Int {
        guard !fcp.isEmpty, let t = Ber.parse(fcp) else { return 0 }
        func find(_ nodes: [Tlv]) -> Int {
            for n in nodes {
                if (n.tag == 0x80 || n.tag == 0x81) && (1...3).contains(n.value.count) { return n.value.reduce(0) { $0 << 8 | Int($1) } }
                if n.constructed { let v = find(n.children); if v > 0 { return v } }
            }
            return 0
        }
        return find(t)
    }

    /// SELECT an EF by identifier in the current application and read it whole. The directive's form (P1=02, P2=04: FCP
    /// returned) first, then the two forms the ID card answers to.
    func readEF(_ fid: UInt16) throws -> [UInt8] {
        let id = [UInt8(fid >> 8), UInt8(fid & 0xFF)]
        var fcp: [UInt8]?; var sw: UInt16 = 0
        for (p1, p2) in [(UInt8(0x02), UInt8(0x04)), (0x00, 0x00), (0x00, 0x0C)] {
            let r = try tx(Self.apdu(0xA4, p1, p2, id, le: p2 == 0x0C ? nil : 0))
            sw = r.sw
            if r.sw == 0x9000 { fcp = r.data; break }
        }
        guard let fcp else { throw CardError.pcsc(Int32(sw), "Select file") }
        let size = Self.fcpSize(fcp)
        let limit = size > 0 ? size : 4096
        var o: [UInt8] = []
        while o.count < limit {
            let n = min(0xE0, limit - o.count)
            let r = try transmit(Self.apdu(0xB0, UInt8(o.count >> 8), UInt8(o.count & 0xFF), le: UInt8(n)))
            if r.sw != 0x9000 && r.sw >> 8 != 0x62 {
                if size > 0 || o.isEmpty { throw CardError.pcsc(Int32(r.sw), "Read binary") }
                break
            }
            o += r.data
            if r.data.isEmpty { break }
        }
        return o
    }

    func read() throws -> VehicleData {
        guard try selectApplication() != nil else { throw CardError.unsupportedForCard }
        var files: [[UInt8]] = []
        for fid in Self.dataFiles {
            do { files.append(try readEF(fid)) } catch { if files.isEmpty { throw error } }   // B and C are optional
        }
        return VehicleParser.parse(files)
    }
}

// MARK: - Diagnostics

/// Diagnostic mode: on a real card, selects applications and files, lists identifiers and sizes, reads files that are
/// open and records the answers WITHOUT personal data: only structure (tags, lengths, kinds of value), never values.
/// It sends no VERIFY / PIN command of any kind.
enum CardDiag {
    private static let knownAids: [(String, String)] = [
        ("SERID", "F381000002534552494401"), ("SERIF", "F381000002534552494601"),
        ("SERRP", "F381000002534552525001"), ("PKCS15", "A000000063504B43532D3135"),
    ]
    private static let vehicleAids: [(String, String)] = [
        ("VL full (SERVL+01)", "F381000002534552564C01"), ("VL prefix (SERVL)", "F381000002534552564C"),
        ("VL (SERVL+040201)", "F381000002534552564C040201"),
        ("eVL-001 (long)", "A0000000183414010065564C2D303031"), ("eVL-001", "A00000001865564C2D303031"),
    ]
    private static let vehicleFiles: [UInt16] = [0xD001, 0xD011, 0xD021, 0xD031, 0xD041, 0xE001, 0xE011, 0xE021, 0xC001, 0xC011, 0xC021]

    static func run(atr: [UInt8]?, appVersion: String, reader: String, transmit: @escaping ([UInt8]) throws -> RegistrationCard.Response) -> String {
        var out: [String] = []
        func L(_ s: String) { out.append(s) }
        let card = RegistrationCard(transmit: transmit)
        L("Super Celik card diagnostics (no personal data: structure only, no PIN commands)")
        L("app: \(appVersion)   reader: \(reader)")
        L("ATR: " + (atr.map { RegistrationCard.hex($0) } ?? "n/a"))
        do {
            L(""); L("== ISO discovery")
            let mf = try card.tx(RegistrationCard.apdu(0xA4, 0x00, 0x00, [0x3F, 0x00], le: 0))
            L("SELECT MF (3F00): SW=\(sw(mf.sw)) data=\(mf.data.count)B")
            if mf.sw == 0x9000, !mf.data.isEmpty { dump(mf.data, "  ", true, &out) }
            readPlain(card, "EF.DIR 2F00", 0x2F00, &out)
            readPlain(card, "EF.ATR 2F01", 0x2F01, &out)
            L(""); L("== Known applications")
            for (n, a) in knownAids { trySelect(card, n, a, false, &out) }
            L(""); L("== Vehicle registration candidates (unconfirmed names)")
            for (n, a) in vehicleAids { trySelect(card, n, a, true, &out) }
        } catch { L("ERROR: \(error.localizedDescription)") }
        L(""); L("end")
        return out.joined(separator: "\n")
    }

    private static func sw(_ v: UInt16) -> String { String(format: "%04X", v) }

    private static func trySelect(_ card: RegistrationCard, _ name: String, _ aid: String, _ files: Bool, _ out: inout [String]) {
        do {
            let r = try card.tx(RegistrationCard.apdu(0xA4, 0x04, 0x00, RegistrationCard.bytes(hex: aid), le: 0))
            out.append("SELECT \(name) \(aid): SW=\(sw(r.sw)) fci=\(r.data.count)B")
            guard r.sw == 0x9000 else { return }
            if !r.data.isEmpty { dump(r.data, "  fci ", true, &out) }
            if files { for fid in vehicleFiles { probeFile(card, fid, &out) } }
        } catch { out.append("SELECT \(name): \(error.localizedDescription)") }
    }

    private static func probeFile(_ card: RegistrationCard, _ fid: UInt16, _ out: inout [String]) {
        let id = [UInt8(fid >> 8), UInt8(fid & 0xFF)]
        var fcp: [UInt8]?; var tried: [String] = []
        for (p1, p2) in [(UInt8(0x02), UInt8(0x04)), (0x00, 0x00), (0x00, 0x0C)] {
            guard let r = try? card.tx(RegistrationCard.apdu(0xA4, p1, p2, id, le: p2 == 0x0C ? nil : 0)) else { tried.append("P1=\(p1)P2=\(p2):err"); continue }
            tried.append(String(format: "P1=%02XP2=%02X:%04X", p1, p2, r.sw))
            if r.sw == 0x9000 { fcp = r.data; break }
        }
        out.append(String(format: "  file %04X: select ", fid) + tried.joined(separator: " "))
        guard let fcp else { return }
        let size = RegistrationCard.fcpSize(fcp)
        if !fcp.isEmpty { dump(fcp, "    fcp ", true, &out) }
        out.append("    size from fcp: \(size > 0 ? String(size) : "n/a")")
        var o: [UInt8] = []; let limit = size > 0 ? min(size, 8192) : 4096; var last: UInt16 = 0x9000
        while o.count < limit {
            guard let r = try? card.tx(RegistrationCard.apdu(0xB0, UInt8(o.count >> 8), UInt8(o.count & 0xFF), le: UInt8(min(0xE0, limit - o.count)))) else { break }
            last = r.sw
            if r.sw != 0x9000 && r.sw >> 8 != 0x62 { break }
            o += r.data
            if r.data.isEmpty { break }
        }
        out.append("    read: \(o.count) bytes, last SW=\(sw(last))")
        if !o.isEmpty { describe(o, "    ", &out) }
    }

    private static func readPlain(_ card: RegistrationCard, _ name: String, _ fid: UInt16, _ out: inout [String]) {
        guard let s = try? card.tx(RegistrationCard.apdu(0xA4, 0x00, 0x0C, [UInt8(fid >> 8), UInt8(fid & 0xFF)])) else { out.append("\(name): error"); return }
        guard s.sw == 0x9000 else { out.append("\(name): select SW=\(sw(s.sw))"); return }
        var o: [UInt8] = []; var last: UInt16 = 0x9000
        while o.count < 1024 {
            guard let b = try? card.tx(RegistrationCard.apdu(0xB0, UInt8(o.count >> 8), UInt8(o.count & 0xFF), le: 0xE0)) else { break }
            last = b.sw
            if b.sw != 0x9000 || b.data.isEmpty { break }
            o += b.data
        }
        out.append("\(name): read \(o.count) bytes, last SW=\(sw(last))")
        if !o.isEmpty { dump(o, "  ", true, &out) }   // EF.DIR / EF.ATR hold application names, not personal data
    }

    /// Structure of a file: BER-TLV, or the ID-card record format [tag LE16][len LE16] after a 4-byte header, or statistics.
    private static func describe(_ d: [UInt8], _ ind: String, _ out: inout [String]) {
        if let t = Ber.parse(d), let f = t.first, f.tag >= 0x40 { out.append(ind + "BER-TLV:"); dump(d, ind + "  ", false, &out); return }
        if d.count > 8 {
            var recs: [String] = []; var p = 4; var good = true
            while p + 4 <= d.count {
                let tag = Int(d[p]) | Int(d[p + 1]) << 8, len = Int(d[p + 2]) | Int(d[p + 3]) << 8
                if p + 4 + len > d.count { good = false; break }
                recs.append(String(format: "%04X/%d ", tag, len) + kind(Array(d[p + 4..<p + 4 + len])))
                p += 4 + len
            }
            if good && !recs.isEmpty && p == d.count {
                out.append(ind + String(format: "records [tag LE16][len LE16] after a 4-byte header (file id %04X, declared %d bytes):", Int(d[0]) | Int(d[1]) << 8, Int(d[2]) | Int(d[3]) << 8))
                for r in recs { out.append(ind + "  " + r) }
                return
            }
        }
        out.append(ind + "unstructured: " + kind(d))
    }

    private static func dump(_ d: [UInt8], _ ind: String, _ showNames: Bool, _ out: inout [String]) {
        guard let t = Ber.parse(d) else { out.append(ind + "(not BER) " + kind(d)); return }
        dumpNodes(t, ind, showNames, &out)
    }

    private static func dumpNodes(_ nodes: [Tlv], _ ind: String, _ showNames: Bool, _ out: inout [String]) {
        for n in nodes {
            if n.constructed { out.append("\(ind)\(n.tagHex) len=\(n.value.count) constructed"); dumpNodes(n.children, ind + "  ", showNames, &out) }
            // application identifiers/names and sizes are not personal; everything else is shown as a kind only
            else if showNames && [0x4F, 0x84, 0x50, 0x80, 0x81, 0x82, 0x83, 0x88].contains(n.tag) {
                out.append("\(ind)\(n.tagHex) len=\(n.value.count) \(RegistrationCard.hex(n.value))")
            } else { out.append("\(ind)\(n.tagHex) len=\(n.value.count) \(kind(n.value))") }
        }
    }

    /// Kind of value without the value: counts of byte classes.
    private static func kind(_ v: [UInt8]) -> String {
        if v.isEmpty { return "empty" }
        var dig = 0, up = 0, lo = 0, hi = 0, zero = 0, other = 0
        for b in v {
            if b == 0 { zero += 1 } else if b >= 0x30 && b <= 0x39 { dig += 1 } else if b >= 0x41 && b <= 0x5A { up += 1 }
            else if b >= 0x61 && b <= 0x7A { lo += 1 } else if b >= 0x80 { hi += 1 } else { other += 1 }
        }
        let cls = dig == v.count ? (v.count == 8 ? "digits(8, date?)" : "digits")
            : zero == v.count ? "zeros"
            : (hi == 0 && other == 0 && zero == 0) ? "ascii-text"
            : (hi > 0 && other < v.count / 2) ? "text+high-bytes" : "binary"
        return "\(cls) [digits=\(dig) upper=\(up) lower=\(lo) high=\(hi) zero=\(zero) other=\(other)]"
    }
}
