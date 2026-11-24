import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#else
import UIKit
#endif

/// A4 printout of the vehicle registration card, matched to the printout of MUP's own reader "Čitač saobraćajne dozvole"
/// (a standard document, like the ID-card printout). The numbers were measured on a scan of that printout: Verdana
/// (bold 11.9 pt for the fields, regular 20.3 pt for the section headings, 25.85 pt for the title), rows on a 19.85 pt
/// grid, text widths within 0.5 pt of the scan. Same numbers as VehiclePrintSpec in Cards.cs (Windows, Linux) and Pdf.kt.
/// Draws into the current graphics context in page coordinates (origin top-left), like MupPrintLayout:
/// an NSView on macOS (VehiclePrintView), a UIGraphicsPDFRenderer page on iOS.
final class VehiclePrintLayout {
    static let pageSize = MupPrintLayout.pageSize
    private let v: VehicleData
    private let loc: Loc
    private let includeJmbg: Bool
    private let printDate: Date

    init(_ v: VehicleData, loc: Loc, includeJmbg: Bool = true, printDate: Date = .now) {
        self.v = v; self.loc = loc; self.includeJmbg = includeJmbg; self.printDate = printDate
    }

    private func font(_ size: CGFloat, bold: Bool) -> PFont {
        PFont(name: bold ? "Verdana-Bold" : "Verdana", size: size) ?? (bold ? PFont.boldSystemFont(ofSize: size) : PFont.systemFont(ofSize: size))
    }

    /// `b` is the baseline measured from the top of the page, `x` the left edge of the text.
    private func text(_ s: String, x: CGFloat, b: CGFloat, size: CGFloat = 11.9, bold: Bool = true, underline: Bool = false) {
        guard !s.isEmpty else { return }
        let f = font(size, bold: bold)
        let color: PColor = size < 9 ? .gray : .black
        // CoreText puts the baseline exactly where asked (the page context is y-down on both macOS (flipped view) and iOS (PDF renderer))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): f, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]))
        guard let ctx = Self.context else { return }
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: b)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        if underline {
            color.setFill()
            PBezierPath(rect: CGRect(x: x, y: b + 0.09 * size + 0.2, width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), height: 0.75)).fill()
        }
    }

    private static var context: CGContext? {
        #if os(macOS)
        NSGraphicsContext.current?.cgContext
        #else
        UIGraphicsGetCurrentContext()
        #endif
    }

    func draw() {
        let size = Self.pageSize
        PColor.white.setFill()
        PBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        let L: CGFloat = 39.4, R: CGFloat = 348.9
        func dash(_ s: String) -> String { s.isEmpty ? "-" : s }
        let d = CardText.date

        text("Čitač saobraćajne dozvole", x: 43.9, b: 76.36, size: 25.85)
        PColor.black.setFill()
        PBezierPath(rect: CGRect(x: 39.2, y: 90.13, width: 506.7, height: 4.39)).fill()
        text("Registarska oznaka: " + v.registrationNumber, x: 42.5, b: 126.66, size: 19.92)

        text("Datum izdavanja: " + d(v.issuingDate), x: L, b: 175.17)
        text("Važi do: " + d(v.expiryDate), x: R, b: 175.17, size: 11.98, bold: false, underline: true)
        text("Saobraćajnu izdao: " + v.stateIssuing, x: L, b: 195.04)
        text("Zabrana otuđenja: " + d(v.saleBan), x: R, b: 195.04)
        // the issuing authority wraps after the first comma ("PU U PANCEVU," / "MINISTARSTVO UNUTRASNJIH POSLOVA REPUBLIKE SRBIJE")
        let auth = v.authorityIssuing.trimmingCharacters(in: .whitespaces)
        if auth.count > 40, let r = auth.range(of: ", ") {
            text(String(auth[..<r.lowerBound]) + ",", x: L, b: 215.40)
            text(String(auth[r.upperBound...]), x: L, b: 229.07)
        } else { text(auth, x: L, b: 229.07) }
        text("Broj saobraćajne: " + v.unambiguousNumber, x: L, b: 249.24)
        text("Serijski broj: " + v.serialNumber, x: L, b: 269.30)

        text("Podaci o vlasniku", x: L, b: 312.02, size: 20.3, bold: false, underline: true)
        let owner = [
            "Vlasnik: " + v.ownerSurname, "Ime vlasnika: " + v.ownerName, "Adresa vlasnika: " + v.ownerAddress,
            "Jmbg vlasnika: " + (includeJmbg ? v.ownerPersonalNo : ""),
            "Korisnik: " + v.userSurname, "Ime korisnika: " + v.userName, "Adresa korisnika: " + v.userAddress,
            "Jmbg korisnika: " + (includeJmbg ? v.userPersonalNo : ""),
        ]
        for (i, s) in owner.enumerated() { text(s, x: L, b: 331.78 + 19.863 * CGFloat(i)) }

        text("Podaci o vozilu", x: L, b: 502.07, size: 20.3, bold: false, underline: true)
        let left = [
            "Datum prve registracije: " + d(v.firstRegistrationDate),
            "Marka: " + v.make + "   Model: " + v.commercialDescription,
            "Tip: " + dash(v.type),
            "Boja: " + v.colour, "Broj šasije: " + v.vin, "Broj motora: " + v.engineNumber,
            "Snaga motora: " + v.maxNetPower, "Odnos snaga/masa: " + v.powerWeightRatio,
            "Kategorija: " + v.category, "Pogonsko gorivo: " + v.fuelType, "Broj mesta za sedenje: " + v.seats,
        ]
        let right = [
            "Godina proizvodnje: " + v.yearOfProduction, "", "",
            "Broj osovina: " + v.axles, "Zapremina motora: " + v.engineCapacity, "Masa: " + v.mass,
            "Nosivost: " + v.load, "Najveća dozvoljena", "masa: " + v.maxLadenMass, "", "Broj mesta za stajanje: " + v.standingPlaces,
        ]
        for i in 0..<left.count {
            let b = 521.53 + 19.793 * CGFloat(i)
            text(left[i], x: L, b: b)
            text(right[i], x: R, b: b)
        }
        // second column of the "Tip" row at x = 90.6 as in the printout; a longer type pushes it right (about 8 pt per extra character)
        text("Homologacijska oznaka: " + dash(v.typeApprovalNumber), x: 90.6 + CGFloat(max(0, ("Tip: " + dash(v.type)).count - 6)) * 8, b: 521.53 + 19.793 * 2)

        // the note about the unverified parser, small and grey at the foot of the page (not part of MUP's printout), wrapped by hand
        let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy"
        var note = "\(loc.x("vehNote"))   \(f.string(from: printDate))"
        var nb: CGFloat = 806
        while !note.isEmpty && nb < 835 {
            var n = note.count
            if n > 125 {
                let head = note.prefix(125)
                n = head.lastIndex(of: " ").map { head.distance(from: head.startIndex, to: $0) } ?? 125
                if n <= 0 { n = 125 }
            }
            text(String(note.prefix(n)).trimmingCharacters(in: .whitespaces), x: 41.5, b: nb, size: 7.5, bold: false)
            note = String(note.dropFirst(n)).trimmingCharacters(in: .whitespaces); nb += 9
        }
    }
}

#if os(macOS)
final class VehiclePrintView: NSView {
    private let layout: VehiclePrintLayout
    init(_ v: VehicleData, loc: Loc, includeJmbg: Bool) {
        layout = VehiclePrintLayout(v, loc: loc, includeJmbg: includeJmbg)
        super.init(frame: NSRect(origin: .zero, size: VehiclePrintLayout.pageSize))
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { layout.draw() }
}

struct VehiclePrintSheet: NSViewRepresentable {
    let v: VehicleData
    let loc: Loc
    var includeJmbg: Bool = true
    func makeNSView(context: Context) -> VehiclePrintView { VehiclePrintView(v, loc: loc, includeJmbg: includeJmbg) }
    func updateNSView(_ view: VehiclePrintView, context: Context) {}
}
#endif
