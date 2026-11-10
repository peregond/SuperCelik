import Foundation

// Shared by the macOS app and the iOS app (ios/SuperCelik.xcodeproj compiles this file too).

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
    case transport(String)          // NFC / connection problem (iOS)
    var errorDescription: String? {
        switch self {
        case .pinWrong(let n): return "Wrong PIN, \(n) tries left"
        case .pinBlocked: return "PIN is blocked (unblock at MUP)"
        case .signature(let m): return "Signature: " + m
        case .chainNotTrusted(let m): return "Certificate chain: " + m
        case .pcsc(let code, let what): return "\(what): PC/SC 0x" + String(UInt32(bitPattern: code), radix: 16)
        case .notImplemented: return "Not implemented"
        case .unsupportedForCard: return "Not supported for this card type"
        case .transport(let m): return m
        }
    }
}
