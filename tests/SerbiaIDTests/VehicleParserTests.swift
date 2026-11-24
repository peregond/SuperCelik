import XCTest
@testable import SerbiaID

/// Synthetic data built from the directive 1999/37/EC (as amended) and the MUP SDK table. Not from a real card.
final class VehicleParserTests: XCTestCase {
    func t(_ tag: Int, _ s: String) -> [UInt8] { Ber.build(tag, Array(s.utf8)) }
    func t(_ tag: Int, _ children: [UInt8]...) -> [UInt8] { Ber.build(tag, children.flatMap { $0 }) }

    func fileA(engineTag: Int = 0xA5, charset: UInt8 = 0) -> [UInt8] {
        t(0x78, t(0x4F, "AID-TEST")) + t(0x71,
            t(0x80, "\u{01}"), Ber.build(0x9F33, Array("SRB".utf8)), Ber.build(0x9F35, Array("MUP".utf8)),
            Ber.build(0x9F37, [charset]), Ber.build(0x9F38, Array("123456".utf8)),
            t(0x81, "BG123AB"), t(0x82, "20150312"),
            t(0xA1, t(0xA2, t(0x83, "Petrovic"), t(0x84, "Marko"), t(0x85, "Ulica 1, Beograd"), t(0x86, "\0"))),
            t(0xA3, t(0x87, "FIAT"), t(0x88, "199A"), t(0x89, "PUNTO")),
            t(0x8A, "ZFA19900000000001"), t(0xA4, t(0x8B, "1500")), t(0x8C, "1100"),
            t(0x8D, "20260312"), t(0x8E, "20250312"), t(0x8F, "e3*2001/116"),
            t(engineTag, t(0x90, "1242"), t(0x91, "44"), t(0x92, "BENZIN")),
            t(0xA6, t(0x94, "5"), t(0x95, "0")))
    }

    func testMandatoryData() {
        let v = VehicleParser.parse([fileA() + [UInt8](repeating: 0, count: 100)])
        XCTAssertEqual(v.registrationNumber, "BG123AB")
        XCTAssertEqual(v.firstRegistrationDate, "12.03.2015")
        XCTAssertEqual(v.expiryDate, "12.03.2026"); XCTAssertEqual(v.issuingDate, "12.03.2025")
        XCTAssertEqual(v.make, "FIAT"); XCTAssertEqual(v.type, "199A"); XCTAssertEqual(v.commercialDescription, "PUNTO")
        XCTAssertEqual(v.vin, "ZFA19900000000001")
        XCTAssertEqual(v.maxLadenMass, "1500"); XCTAssertEqual(v.mass, "1100")
        XCTAssertEqual(v.engineCapacity, "1242"); XCTAssertEqual(v.maxNetPower, "44"); XCTAssertEqual(v.fuelType, "BENZIN")
        XCTAssertEqual(v.seats, "5"); XCTAssertEqual(v.standingPlaces, "0")
        XCTAssertEqual(v.stateIssuing, "SRB"); XCTAssertEqual(v.unambiguousNumber, "123456")
        XCTAssertEqual(v.typeApprovalNumber, "e3*2001/116")
        XCTAssertTrue(v.unknownTags.isEmpty); XCTAssertFalse(v.signatureVerified)
    }

    func testHolderBecomesOwner() {
        let v = VehicleParser.parse([fileA()])
        XCTAssertEqual(v.ownerSurname, "Petrovic"); XCTAssertEqual(v.ownerName, "Marko"); XCTAssertEqual(v.ownerAddress, "Ulica 1, Beograd")
    }

    func testEngineUnderTag5A() {
        let v = VehicleParser.parse([fileA(engineTag: 0x5A)])
        XCTAssertEqual(v.engineCapacity, "1242"); XCTAssertEqual(v.fuelType, "BENZIN")
    }

    func testOptionalAndNationalFiles() {
        let b = t(0x78, t(0x4F, "AID-TEST")) + t(0x72,
            t(0xA1, t(0xA7, t(0x83, "Vlasnik"), t(0x84, "Ime"), t(0x85, "Adresa vlasnika")),
                    t(0xA9, t(0x83, "Korisnik"), t(0x84, "Ime2"), t(0x85, "Adresa korisnika"))),
            t(0x98, "M1"), t(0x99, "2"), Ber.build(0x9F24, Array("CRVENA".utf8)))
        let c = t(0x78, t(0x4F, "AID-TEST")) + t(0x72, t(0xC1, "20300101"), t(0xC2, "0101990710000"), t(0xC3, "0202985710001"),
                                                 t(0xC4, "480"), t(0xC5, "2014"), t(0xC9, "SN-0001"))
        let v = VehicleParser.parse([fileA(), b, c])
        XCTAssertEqual(v.ownerSurname, "Vlasnik"); XCTAssertEqual(v.userAddress, "Adresa korisnika")
        XCTAssertEqual(v.category, "M1"); XCTAssertEqual(v.axles, "2"); XCTAssertEqual(v.colour, "CRVENA")
        XCTAssertEqual(v.saleBan, "20300101"); XCTAssertEqual(v.ownerPersonalNo, "0101990710000")
        XCTAssertEqual(v.userPersonalNo, "0202985710001"); XCTAssertEqual(v.load, "480")
        XCTAssertEqual(v.yearOfProduction, "2014"); XCTAssertEqual(v.serialNumber, "SN-0001")
    }

    func testCyrillic8859_5() {
        // "Петровић" in ISO 8859-5: П=0xBF е=0xD5 т=0xE2 р=0xE0 о=0xDE в=0xD2 и=0xD8 ћ=0xFB
        let f = t(0x71, Ber.build(0x9F37, [1]), t(0xA1, Ber.build(0xA7, Ber.build(0x83, [0xBF, 0xD5, 0xE2, 0xE0, 0xDE, 0xD2, 0xD8, 0xFB]))))
        let v = VehicleParser.parse([f])
        XCTAssertEqual(v.ownerSurname, "Петровић"); XCTAssertEqual(v.charsetTag, 1)
    }

    func testUtf8Accepted() {
        let v = VehicleParser.parse([t(0x71, Ber.build(0x81, Array("Ćuprija".utf8)))])
        XCTAssertEqual(v.registrationNumber, "Ćuprija")
    }

    func testLongLengthAndTwoByteTag() {
        let big = String(repeating: "A", count: 300)
        let v = VehicleParser.parse([t(0x71, t(0xA1, t(0xA7, t(0x85, big))))])
        XCTAssertEqual(v.ownerAddress.count, 300)
        XCTAssertEqual(Ber.parse(Ber.build(0x9F33, [0x41]))?.first?.tag, 0x9F33)
    }

    func testUnknownTagsWithoutValues() {
        let v = VehicleParser.parse([t(0x71, t(0x81, "X"), t(0xDF55, "secret"))])
        XCTAssertEqual(v.unknownTags, ["DF55/6"])
    }

    func testGarbageDoesNotCrash() {
        XCTAssertNil(Ber.parse([0x71, 0x05, 1, 2]))
        XCTAssertEqual(VehicleParser.parse([[0x71, 0x05, 1, 2], []]).registrationNumber, "")
    }

    func testRowsAndTexts() {
        let rows = VehicleRows.build(VehicleRows.demo())
        XCTAssertTrue(rows.contains { $0.key == "vRegNo" && $0.value == "BG 123-AB" })
        XCTAssertFalse(rows.contains { $0.key == "vUser" })
        var d = VehicleRows.demo(); d.userName = "A"; d.userSurname = "B"; d.userAddress = "C"; d.userPersonalNo = "D"; d.saleBan = "20300101"
        let keys = Set(VehicleRows.build(d).map { $0.key }).union(VehicleRows.sensitive)
            .union(["vehNote", "vehTitle", "cardUnknown", "diagTitle", "diagText", "diagRun", "diagCopy", "diagCopied"])
        let loc = Loc.shared
        for lang in AppLanguage.allCases {
            loc.language = lang
            for k in keys { XCTAssertNotEqual(loc.x(k), k, "\(lang) \(k)"); XCTAssertFalse(loc.x(k).isEmpty) }
        }
        loc.language = .srCyrl
        XCTAssertEqual(loc.x("vRegNo"), "Регистарски број")
        loc.language = .en
    }
}

#if os(macOS)
import AppKit
final class VehiclePrintTests: XCTestCase {
    func testPrintoutIsOnePagePdf() throws {
        let view = VehiclePrintView(VehicleRows.demo(), loc: Loc.shared, includeJmbg: true)
        let data = view.dataWithPDF(inside: view.bounds)
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
        XCTAssertGreaterThan(data.count, 1500)
        if let path = ProcessInfo.processInfo.environment["VEHICLE_PDF_OUT"] { try data.write(to: URL(fileURLWithPath: path)) }
    }
}
#endif
