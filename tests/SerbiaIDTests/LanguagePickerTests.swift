import XCTest
@testable import SerbiaID

final class LanguagePickerTests: XCTestCase {
    func testSerbianFirstInBothScriptsThenTheOthers() {
        XCTAssertEqual(AppLanguage.pickerTop, [.sr, .srCyrl])
        XCTAssertEqual(AppLanguage.pickerRest.count, 9)
        XCTAssertEqual(Set(AppLanguage.pickerTop + AppLanguage.pickerRest).count, AppLanguage.allCases.count)
    }

    func testEveryInterfaceLanguageNamesEveryPickerEntry() {
        let loc = Loc.shared
        let was = loc.language
        defer { loc.language = was }
        for lang in AppLanguage.allCases {
            loc.language = lang
            for entry in AppLanguage.allCases {
                let label = loc.pickerLabel(entry)
                XCTAssertTrue(label.hasPrefix(entry.flag), "\(lang) \(entry)")
                XCTAssertGreaterThan(label.count, entry.flag.count + 2, "\(lang) \(entry)")
            }
            for kind in DemoKind.allCases { XCTAssertNotEqual(loc.x(kind.labelKey), kind.labelKey, "\(lang) \(kind)") }
        }
    }

    func testSerbianCyrillicInterfaceNamesTheScriptsInCyrillic() {
        let loc = Loc.shared
        let was = loc.language
        defer { loc.language = was }
        loc.language = .srCyrl
        XCTAssertTrue(loc.pickerLabel(.sr).hasSuffix("Латиница"))
        XCTAssertTrue(loc.pickerLabel(.srCyrl).hasSuffix("Ћирилица"))
    }
}
