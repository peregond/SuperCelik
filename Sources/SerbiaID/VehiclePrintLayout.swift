import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#else
import UIKit
#endif

/// A4 printout of the vehicle registration card, laid out after the printout of MUP's own reader "Čitač saobraćajne
/// dozvole" (a standard document: its title, order of the fields, labels in Serbian Latin and positions are kept; the
/// typeface is the nearest one available). Same numbers as VehiclePrintSpec in Cards.cs (Windows, Linux) and Pdf.kt.
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

    /// `y` is the vertical centre of the first line.
    private func text(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat = 10.5, bold: Bool = true, underline: Bool = false,
                      width: CGFloat = 0, color: PColor = .black) {
        guard !s.isEmpty else { return }
        var attrs: [NSAttributedString.Key: Any] = [.font: font(size, bold: bold), .foregroundColor: color]
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        let str = NSAttributedString(string: s, attributes: attrs)
        let w = width > 0 ? width : 520
        let h = ceil(str.boundingRect(with: CGSize(width: w, height: 1000), options: [.usesLineFragmentOrigin], context: nil).height)
        str.draw(in: CGRect(x: x, y: y - size * 0.6, width: w, height: h + 2))
    }

    func draw() {
        let size = Self.pageSize
        PColor.white.setFill()
        PBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        let left: CGFloat = 41.5, right: CGFloat = 350
        func dash(_ s: String) -> String { s.isEmpty ? "-" : s }
        let d = CardText.date

        text("Čitač saobraćajne dozvole", x: 45, y: 64, size: 22)
        PColor.black.setFill()
        PBezierPath(rect: CGRect(x: 39, y: 84 - 1.5, width: 507, height: 3)).fill()
        text("Registarska oznaka: " + v.registrationNumber, x: 42.5, y: 119, size: 18)

        text("Datum izdavanja: " + d(v.issuingDate), x: left, y: 171)
        text("Važi do: " + d(v.expiryDate), x: right, y: 171, bold: false, underline: true)
        text("Saobraćajnu izdao: " + v.stateIssuing, x: left, y: 190)
        text("Zabrana otuđenja: " + d(v.saleBan), x: right, y: 190)
        text(v.authorityIssuing, x: left, y: 213, width: 470)
        text("Broj saobraćajne: " + v.unambiguousNumber, x: left, y: 252)
        text("Serijski broj: " + v.serialNumber, x: left, y: 272)

        text("Podaci o vlasniku", x: left, y: 303, size: 16.5, bold: false, underline: true)
        let owner = [
            "Vlasnik: " + v.ownerSurname, "Ime vlasnika: " + v.ownerName, "Adresa vlasnika: " + v.ownerAddress,
            "Jmbg vlasnika: " + (includeJmbg ? v.ownerPersonalNo : ""),
            "Korisnik: " + v.userSurname, "Ime korisnika: " + v.userName, "Adresa korisnika: " + v.userAddress,
            "Jmbg korisnika: " + (includeJmbg ? v.userPersonalNo : ""),
        ]
        for (i, s) in owner.enumerated() { text(s, x: left, y: 327.6 + 19.2 * CGFloat(i), width: 500) }

        text("Podaci o vozilu", x: left, y: 495.4, size: 16.5, bold: false, underline: true)
        let car = [
            "Datum prve registracije: " + d(v.firstRegistrationDate),
            "Marka: " + v.make + "   Model: " + v.commercialDescription,
            "Tip: " + dash(v.type) + "   Homologacijska oznaka: " + dash(v.typeApprovalNumber),
            "Boja: " + v.colour, "Broj šasije: " + v.vin, "Broj motora: " + v.engineNumber,
            "Snaga motora: " + v.maxNetPower, "Odnos snaga/masa: " + v.powerWeightRatio,
            "Kategorija: " + v.category, "Pogonsko gorivo: " + v.fuelType, "Broj mesta za sedenje: " + v.seats,
        ]
        for (i, s) in car.enumerated() { text(s, x: left, y: 516.6 + 19.1 * CGFloat(i)) }
        text("Godina proizvodnje: " + v.yearOfProduction, x: right, y: 516.6)
        let rightCol = ["Broj osovina: " + v.axles, "Zapremina motora: " + v.engineCapacity, "Masa: " + v.mass,
                        "Nosivost: " + v.load, "Najveća dozvoljena"]
        for (i, s) in rightCol.enumerated() { text(s, x: right, y: 573.8 + 19.9 * CGFloat(i)) }
        text("masa: " + v.maxLadenMass, x: right, y: 573.8 + 19.9 * 4 + 17)
        text("Broj mesta za stajanje: " + v.standingPlaces, x: right, y: 707.6)

        let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy"
        text("\(loc.x("vehNote"))   \(f.string(from: printDate))", x: 41.5, y: 810, size: 7.5, bold: false, width: 512, color: .gray)
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
