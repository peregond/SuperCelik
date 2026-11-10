import Foundation
#if os(macOS)
import AppKit
typealias PColor = NSColor
typealias PFont = NSFont
typealias PImage = NSImage
typealias PBezierPath = NSBezierPath
#else
import UIKit
typealias PColor = UIColor
typealias PFont = UIFont
typealias PImage = UIImage
typealias PBezierPath = UIBezierPath
#endif

// MARK: - MUP printout ("ČITAČ ELEKTRONSKE LIČNE KARTE: ŠTAMPA PODATAKA")
//
// This reproduces the printout of the official MUP Čelik application one-to-one:
// same A4 page, positions (in points), line widths, font sizes, labels and footnotes.
// It is a standard document — do not restyle it. Shared by the macOS and iOS apps.

/// The printout in page coordinates (A4, 595 x 842 pt, origin top-left). Draws into the current
/// graphics context: an NSView on macOS (MupPrintView), a UIGraphicsPDFRenderer page on iOS.
/// The same code draws both, so the iOS PDF is the same MUP form as the macOS printout.
final class MupPrintLayout {
    private let p: PersonalData
    private let includeJmbg: Bool
    private let printDate: Date

    static let pageSize = CGSize(width: 595.28, height: 841.89)
    private let leftMargin: CGFloat = 58.8
    private let rightMargin: CGFloat = 535
    private let textLeftMargin: CGFloat = 67.3
    private var y: CGFloat = 0
    private var lineWidth: CGFloat = 1
    private var fontSize: CGFloat = 13.5
    private var kern: CGFloat = -0.1

    init(_ p: PersonalData, includeJmbg: Bool = true, printDate: Date = .now) {
        self.p = p; self.includeJmbg = includeJmbg; self.printDate = printDate
    }

    func draw() {
        PColor.white.setFill()
        PBezierPath(rect: CGRect(origin: .zero, size: Self.pageSize)).fill()
        y = 0; lineWidth = 1; fontSize = 13.5; kern = -0.1
        switch p.cardType {
        case .if2020: drawForeigner(permit: false)
        case .rp2024: drawForeigner(permit: true)
        default: drawRegular()
        }
    }

    // MARK: Pages

    private func drawRegular() {
        header(titleY: 68.5, ruleY: 88)
        photo(top: 102.8)
        y = 276
        line(1.08)
        section("Podaci o građaninu", first: true)
        let f = p.fixed, v = p.variable
        row("Prezime:", f.surname)
        row("Ime:", f.givenName)
        row("Ime jednog roditelja:", f.parentGivenName)
        row("Datum rođenja:", Self.date(f.dateOfBirth))
        row("Mesto rođenja\nopština i država:", Self.join(f.placeOfBirth, f.communityOfBirth, f.stateOfBirth))
        row(addressLabel, address)
        row("Datum promene adrese:", Self.date(v.addressDate))
        if includeJmbg { row("JMBG:", f.personalNumber) }
        row("Pol:", f.sex)
        documentSection(withName: false)
        printDateLine()
        if y < 700 { y = 730.6 }
        line(0.83)
        fontSize = 9
        y += 10
        notes([
            "1. U čipu lične karte, podaci o imenu i prezimenu imaoca lične karte ispisani su na nacionalnom pismu onako kako su",
            "ispisani na samom obrascu lične karte, dok su ostali podaci ispisani latiničkim pismom.",
            "2. Ako se ime lica sastoji od dve reči čija je ukupna dužina između 20 i 30 karaktera ili prezimena od dve reči čija je",
            "ukupna dužina između 30 i 36 karaktera, u čipu lične karte izdate pre 18.08.2014. godine, druga reč u imenu ili prezimenu",
            "skraćuje se na prva dva karaktera",
        ])
        y += 15.7
        line(nil)
    }

    private func drawForeigner(permit: Bool) {
        header(titleY: 64.95, ruleY: 79.8)
        photo(top: 86)
        y = 250
        line(1.08)
        section("Podaci o strancu", first: true)
        let f = p.fixed, v = p.variable
        row("Prezime:", f.surname)
        row("Ime:", f.givenName)
        row("Državljanstvo:", f.nationalityFull)
        row("Datum rođenja:", Self.date(f.dateOfBirth))
        if permit {
            row("Mesto rođenja,\nopština i država:", Self.join(f.placeOfBirth, f.communityOfBirth, f.stateOfBirth))
            row(addressLabel, address)
        } else {
            row("Osnov boravka:", f.purposeOfStay)
            row(addressLabel, Self.join(v.state, address))
        }
        row("Datum promene adrese:", Self.date(v.addressDate))
        if includeJmbg { row("Evidencijski broj\nstranca:", f.personalNumber) }
        row("Pol:", f.sex)
        if permit {
            row("Osnov boravka:", f.purposeOfStay)
            row("Napomena:", f.eNote)
        }
        documentSection(withName: permit)
        printDateLine()
        line(0.83)
        fontSize = 9
        y += 4
        notes(permit ? [
            "1. U čipu dozvole za privremeni boravak i rad, podaci o imenu i prezimenu imaoca dozvole ispisani su onako kako su",
            "ispisani na samom obrascu dozvole za privremeni boravak latiničnim pismom.",
            "2. Ako se ime ili prezime stranca sastoji od dve ili više reči čija dužina prelazi 30 karaktera za ime, odnosno 36 karaktera",
            "za prezime u čip se upisuje puno ime stranca, a na obrascu dozvole za privremeni boravak se upisuje do 30 karaktera za",
            "ime, odnosno 36 karaktera za prezime.",
        ] : [
            "1. U čipu lične karte za strance, podaci o imenu i prezimenu stranca ispisani su onako kako su ispisani na samom",
            "obrascu lične karte za stranca latiničnim pismom.",
            "2. Ako se ime ili prezime stranca sastoji od dve ili više reči čija dužina prelazi 30 karaktera za ime, odnosno 36",
            "karaktera za prezime, u čip se upisuje puno ime i prezime stranca, a na obrascu lične karte za stranca se upisuje do",
            "30 karaktera za ime, odnosno 36 karaktera za prezime.",
        ])
        y += 9.7
        line(nil)
    }

    // MARK: Blocks

    private func header(titleY: CGFloat, ruleY: CGFloat) {
        y = 59.041
        line(0.83)
        kern = -0.2
        text("ČITAČ ELEKTRONSKE LIČNE KARTE: ŠTAMPA PODATAKA", x: textLeftMargin + 1, y: titleY)
        kern = -0.1
        y = ruleY
        line(nil)
    }

    private func photo(top: CGFloat) {
        let frame = CGRect(x: leftMargin, y: top, width: 179 - leftMargin, height: 159)
        if let d = p.portrait, let img = PImage(data: d) {
            let r = CGRect(x: leftMargin, y: top, width: 119.9, height: 159)
            #if os(macOS)
            img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            #else
            img.draw(in: r)
            #endif
        }
        PColor.black.setStroke()
        let path = PBezierPath(rect: frame)
        path.lineWidth = 0.48
        path.stroke()
        lineWidth = 0.48
    }

    private func section(_ title: String, first: Bool) {
        if !first {
            y -= 8.67
            line(nil)
        }
        y += first ? 8 : 9
        if first { fontSize = 11.1 }
        text(title, x: textLeftMargin, y: y)
        y += 16
        line(nil)
        y += 9
    }

    private func documentSection(withName: Bool) {
        section("Podaci o dokumentu", first: false)
        let d = p.document
        if withName { row("Naziv dokumenta:", d.documentName) }
        row("Dokument izdaje:", d.issuingAuthority)
        row("Broj dokumenta:", d.docRegNo)
        row("Datum izdavanja:", Self.date(d.issuingDate))
        row("Važi do:", Self.date(d.expiryDate))
    }

    private func printDateLine() {
        y -= 8.67
        line(nil)
        y += 3
        line(nil)
        y += 9
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd.MM.yyyy."
        text("Datum štampe: " + f.string(from: printDate), x: textLeftMargin, y: y)
        y += 19
    }

    private func notes(_ lines: [String]) {
        for (i, s) in lines.enumerated() {
            if i > 0 { y += 9.7 }
            text(s, x: leftMargin, y: y)
        }
    }

    /// Label column 120 pt wide at the text margin, value column 350 pt wide 128 pt to the right;
    /// wrapped lines are 12 pt apart, rows 24.67 pt apart.
    private func row(_ label: String, _ value: String) {
        let top = y
        let l = wrap(label, width: 120), v = wrap(value, width: 350)
        for (i, s) in l.enumerated() { text(s, x: textLeftMargin, y: top + CGFloat(i) * 12) }
        for (i, s) in v.enumerated() { text(s, x: textLeftMargin + 128, y: top + CGFloat(i) * 12) }
        y = top + CGFloat(max(l.count, v.count, 1) - 1) * 12 + 24.67
    }

    // MARK: Primitives

    private var attrs: [NSAttributedString.Key: Any] {
        let font = PFont(name: "Arial", size: fontSize) ?? PFont(name: "Helvetica", size: fontSize)!
        return [.font: font, .foregroundColor: PColor.black, .kern: kern]
    }

    private func text(_ s: String, x: CGFloat, y: CGFloat) {
        (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }

    /// Horizontal rule across the page at the current y; `nil` keeps the previous width.
    private func line(_ width: CGFloat?) {
        if let width { lineWidth = width }
        PColor.black.setStroke()
        let path = PBezierPath()
        path.move(to: CGPoint(x: leftMargin, y: y))
        #if os(macOS)
        path.line(to: CGPoint(x: rightMargin, y: y))
        #else
        path.addLine(to: CGPoint(x: rightMargin, y: y))
        #endif
        path.lineWidth = lineWidth
        path.stroke()
    }

    private func wrap(_ s: String, width: CGFloat) -> [String] {
        var out: [String] = []
        let a = attrs
        for para in s.components(separatedBy: "\n") {
            var cur = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: true) {
                let next = cur.isEmpty ? String(word) : cur + " " + String(word)
                if !cur.isEmpty, (next as NSString).size(withAttributes: a).width > width {
                    out.append(cur); cur = String(word)
                } else { cur = next }
            }
            out.append(cur)
        }
        return out
    }

    // MARK: Formatting (as on the MUP printout)

    private var addressLabel: String {
        p.variable.addressLabel.lowercased() == "prebivalište" ? "Prebivalište:" : "Prebivalište\ni adresa stana:"
    }

    /// "MESTO, OPŠTINA, ULICA 12A/3/7"
    private var address: String {
        let v = p.variable
        var street = v.street
        if !v.houseNumber.isEmpty || !v.houseLetter.isEmpty || !v.entrance.isEmpty {
            street += " " + v.houseNumber + v.houseLetter
            if !v.floor.isEmpty { street += "/" + v.floor }
            if !v.apartmentNumber.isEmpty { street += "/" + v.apartmentNumber }
        }
        return Self.join(v.place, v.community, street)
    }

    private static func join(_ parts: String...) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// "dd.MM.yyyy" -> "dd.MM.yyyy."; a date with year 0000 is "Nije dostupan".
    private static func date(_ s: String) -> String {
        let parts = s.split(separator: ".")
        guard parts.count == 3, parts[2].count == 4 else { return s }
        if parts[2] == "0000" { return "Nije dostupan" }
        return s.hasSuffix(".") ? s : s + "."
    }
}
