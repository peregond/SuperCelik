import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#else
import UIKit
#endif

/// A4 printout of the vehicle registration card data: a plain table (label, value), not a copy of any official form.
/// Draws into the current graphics context in page coordinates (origin top-left), like MupPrintLayout:
/// an NSView on macOS (VehiclePrintView), a UIGraphicsPDFRenderer page on iOS.
final class VehiclePrintLayout {
    static let pageSize = MupPrintLayout.pageSize
    private let rows: [(key: String, value: String)]
    private let v: VehicleData
    private let loc: Loc
    private let printDate: Date

    init(_ v: VehicleData, loc: Loc, includeJmbg: Bool = true, printDate: Date = .now) {
        self.v = v; self.loc = loc; self.printDate = printDate
        rows = VehicleRows.build(v, includeJmbg: includeJmbg)
    }

    private func text(_ s: String, _ size: CGFloat, bold: Bool, color: PColor = .black, at p: CGPoint, width: CGFloat) -> CGFloat {
        let font = bold ? PFont.boldSystemFont(ofSize: size) : PFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: s, attributes: attrs)
        let h = ceil(str.boundingRect(with: CGSize(width: width, height: 1000), options: [.usesLineFragmentOrigin], context: nil).height)
        str.draw(in: CGRect(x: p.x, y: p.y, width: width, height: h + 2))
        return h
    }

    func draw() {
        let size = Self.pageSize
        PColor.white.setFill()
        PBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        var y: CGFloat = 52
        y += text(loc.x("vehTitle"), 20, bold: true, at: CGPoint(x: 50, y: y), width: size.width - 100) + 8
        y += text(v.registrationNumber, 14, bold: true, at: CGPoint(x: 50, y: y), width: size.width - 100) + 8
        PColor.black.setFill()
        PBezierPath(rect: CGRect(x: 50, y: y, width: size.width - 100, height: 1.2)).fill()
        y += 12
        // the step shrinks a little for many rows; the font stays readable
        let step = min(20, (size.height - y - 70) / CGFloat(max(1, rows.count)))
        let font: CGFloat = step >= 18 ? 11 : 9.5
        for r in rows {
            _ = text(loc.x(r.key), font, bold: false, color: .darkGray, at: CGPoint(x: 50, y: y), width: 190)
            _ = text(r.value, font, bold: true, at: CGPoint(x: 245, y: y), width: size.width - 245 - 50)
            y += step
        }
        let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy"
        _ = text("\(loc.x("vehNote"))   \(f.string(from: printDate))", 8, bold: false, color: .gray,
                 at: CGPoint(x: 50, y: size.height - 44), width: size.width - 100)
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
