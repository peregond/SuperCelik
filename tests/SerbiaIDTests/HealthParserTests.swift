import XCTest
@testable import SerbiaID

/// Synthetic blocks built from docs/health-card-protocol.md (the layout recovered from the official reader). Not from a real card.
final class HealthParserTests: XCTestCase {
    func u(_ s: String) -> [UInt8] { Array(s.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } }
    func a(_ s: String) -> [UInt8] { Array(s.utf8) }
    func n(_ v: Int, _ size: Int) -> [UInt8] { (0..<size).map { UInt8((v >> (8 * $0)) & 0xFF) } }
    func el(_ tag: Int, _ v: [UInt8]) -> [UInt8] { [UInt8(tag & 0xFF), UInt8(tag >> 8), UInt8(v.count & 0xFF), UInt8(v.count >> 8)] + v }
    func block(_ id: UInt16, _ els: [UInt8]...) -> [UInt8] {
        let body = els.flatMap { $0 }
        return [UInt8(id & 0xFF), UInt8(id >> 8), UInt8(body.count & 0xFF), UInt8(body.count >> 8)] + body
    }

    func doc() -> [UInt8] {
        block(0x0D01, el(0x611, u("RFZO")), el(0x612, a("100000000")), el(0x613, a("00000000001")), el(0x615, a("01012024")),
              el(0x616, a("01012029")), el(0x617, a("0123456789ABCDEF")), el(0x618, a("sr")))
    }
    func fix() -> [UInt8] {
        block(0x0D02, el(0x621, a("00000000001")), el(0x622, u("Петровић")), el(0x623, u("Petrovic")),
              el(0x624, u("Марко")), el(0x625, u("Marko")), el(0x626, a("01011990")))
    }
    func card(permanent: Bool = false, expiry: Bool = true) -> [UInt8] {
        block(0x0D03, el(0x630, a("00000000001")), el(0x631, a("01012024")), expiry ? el(0x632, a("31122030")) : [], el(0x633, n(permanent ? 1 : 0, 1)))
    }
    func admin() -> [UInt8] {
        block(0x0D04, el(0x640, a("00000000001")), el(0x641, u("Јован")), el(0x643, n(2, 2)), el(0x644, a("0101990710000")),
              el(0x645, u("Кнез Михаилова")), el(0x646, a("11000")), el(0x648, u("Београд")), el(0x64A, u("1")),
              el(0x64E, a("010")), el(0x64F, u("Запослени")), el(0x658, a("01012015")), el(0x65A, u("Србија")))
    }

    func testParsesAllBlocks() {
        let h = HealthParser.parse(document: doc(), fixed: fix(), card: card(), admin: admin())
        XCTAssertTrue(h.problems.isEmpty); XCTAssertTrue(h.unknownTags.isEmpty)
        XCTAssertEqual(h.insurerName, "RFZO"); XCTAssertEqual(h.cardId, "00000000001")
        XCTAssertEqual(h.issueDate, "01.01.2024")
        XCTAssertEqual(h.expiryDate, "31.12.2030")            // the validity block wins over the document block
        XCTAssertEqual(h.chipSerial, "0123456789ABCDEF")
        XCTAssertEqual(h.surname, "Петровић"); XCTAssertEqual(h.surnameLatin, "Petrovic"); XCTAssertEqual(h.fullName, "Марко Петровић")
        XCTAssertEqual(h.dateOfBirth, "01.01.1990"); XCTAssertEqual(h.insurantNumber, "00000000001")
        XCTAssertEqual(h.gender, "Ž"); XCTAssertEqual(h.personalNumber, "0101990710000"); XCTAssertEqual(h.parentName, "Јован")
        XCTAssertEqual(h.basisCode, "010"); XCTAssertEqual(h.basisDescription, "Запослени")
        XCTAssertEqual(h.insuredFrom, "01.01.2015"); XCTAssertEqual(h.country, "Србија")
        XCTAssertFalse(h.permanent)
    }

    func testGenderNumberMapsToLetters() {
        XCTAssertEqual(HealthParser.parse(document: doc(), fixed: fix(), card: card(), admin: block(0x0D04, el(0x643, n(1, 2)))).gender, "M")
    }

    func testPermanentCardHasNoValidUntilRow() {
        let h = HealthParser.parse(document: doc(), fixed: fix(), card: card(permanent: true, expiry: false), admin: admin())
        XCTAssertTrue(h.permanent)
        XCTAssertEqual(h.expiryDate, "01.01.2029")            // falls back to the document block
        let keys = HealthRows.build(h).map { $0.key }
        XCTAssertFalse(keys.contains("hValidUntil")); XCTAssertTrue(keys.contains("hPermanent"))
    }

    func testWrongBlockIdIsReportedNotParsed() {
        var wrong = fix(); wrong[0] = 0x09
        let h = HealthParser.parse(document: doc(), fixed: wrong, card: card(), admin: admin())
        XCTAssertTrue(h.problems.contains { $0.hasPrefix("0D02") })
        XCTAssertEqual(h.surname, "")
    }

    func testDeclaredLengthLargerThanFileIsRejected() {
        var f = fix(); f[2] = 0xFF; f[3] = 0x7F
        XCTAssertNil(HealthParser.records(f, expectedId: 0x0D02))
        XCTAssertEqual(HealthParser.parse(document: nil, fixed: f, card: nil, admin: nil).problems.count, 4)
    }

    func testMissingBlockLeavesTheRest() {
        let h = HealthParser.parse(document: doc(), fixed: fix(), card: nil, admin: nil)
        XCTAssertEqual(h.givenName, "Марко"); XCTAssertEqual(h.insurerName, "RFZO"); XCTAssertEqual(h.expiryDate, "01.01.2029")
        XCTAssertEqual(h.problems.count, 2)
    }

    func testUnknownTagsAreLoggedByStructureOnly() {
        let h = HealthParser.parse(document: nil, fixed: block(0x0D02, el(0x6FF, a("secret"))), card: nil, admin: nil)
        XCTAssertTrue(h.unknownTags.contains("0D02/6FF/6"))
        XCTAssertFalse(h.unknownTags.contains { $0.contains("secret") })
    }

    func testOddLengthUtf16FallsBackToUtf8() {
        XCTAssertEqual(HealthParser.parse(document: nil, fixed: block(0x0D02, el(0x624, a("Ana"))), card: nil, admin: nil).givenName, "Ana")
    }

    func testRowsAreGroupedAndHideEmptyOnes() {
        let h = HealthParser.parse(document: doc(), fixed: fix(), card: card(), admin: admin())
        let secs = HealthRows.sections(h).filter { !$0.rows.isEmpty }.map { $0.title }
        XCTAssertEqual(secs.first, "hSecPerson")
        XCTAssertFalse(secs.contains("hSecCarrier")); XCTAssertFalse(secs.contains("hSecTaxpayer"))
        XCTAssertFalse(HealthRows.build(h, includeJmbg: false).contains { $0.key == "hJmbg" })
        XCTAssertTrue(HealthRows.build(h).contains { $0.key == "hAddress" && $0.value.contains("Кнез Михаилова 1") })
    }

    func testDemoHasEverySectionAndEveryKeyHasAText() {
        let secs = HealthRows.sections(HealthRows.demo()).filter { !$0.rows.isEmpty }.map { $0.title }
        XCTAssertEqual(secs, ["hSecPerson", "hSecCard", "hSecInsurance", "hSecTaxpayer"])
        var keys = Set(secs); for s in HealthRows.sections(HealthRows.demo()) { for r in s.rows { keys.insert(r.key) } }
        keys.formUnion(["hSecCarrier", "hTitle", "hNote", "hCarrierName", "hCarrierLbo", "hCarrierJmbg", "hRelation", "hFamilyMember", "hPermanent"])
        for lang in AppLanguage.allCases {
            let loc = Loc.shared; let old = loc.language; loc.language = lang
            for k in keys { XCTAssertTrue(loc.x(k) != k && !loc.x(k).isEmpty, "\(lang) \(k)") }
            loc.language = old
        }
    }
}
