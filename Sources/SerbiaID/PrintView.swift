import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MUP printout: the drawing code is in MupPrintLayout.swift (shared with iOS). Do not restyle it.

/// AppKit view that draws the MUP printout (layout: MupPrintLayout.swift).
final class MupPrintView: NSView {
    private let layout: MupPrintLayout
    static let pageSize = NSSize(width: MupPrintLayout.pageSize.width, height: MupPrintLayout.pageSize.height)

    init(_ p: PersonalData, includeJmbg: Bool = true, printDate: Date = .now) {
        layout = MupPrintLayout(p, includeJmbg: includeJmbg, printDate: printDate)
        super.init(frame: NSRect(origin: .zero, size: Self.pageSize))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) { layout.draw() }
}

/// SwiftUI wrapper used by the in-app print preview.
struct PrintSheet: NSViewRepresentable {
    let p: PersonalData
    let loc: Loc
    var includeJmbg: Bool = true

    func makeNSView(context: Context) -> MupPrintView { MupPrintView(p, includeJmbg: includeJmbg) }
    func updateNSView(_ view: MupPrintView, context: Context) {}
}

enum Printer {
    @MainActor private static func makeView(_ p: PersonalData, includeJmbg: Bool) -> NSView {
        MupPrintView(p, includeJmbg: includeJmbg)
    }

    private static func baseInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = MupPrintView.pageSize
        info.orientation = .portrait
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.horizontalPagination = .clip; info.verticalPagination = .clip
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        return info
    }

    /// Opens the standard macOS print dialog.
    @MainActor static func print(_ p: PersonalData, loc: Loc, includeJmbg: Bool = true) {
        let op = NSPrintOperation(view: makeView(p, includeJmbg: includeJmbg), printInfo: baseInfo())
        op.showsPrintPanel = true
        op.run()
    }

    /// Asks for a file name and writes the vector PDF: the same page the print dialog's "Save as PDF" gives.
    /// The view draws itself straight into a one-page A4 PDF (no NSPrintOperation, so nothing from the print
    /// system's saved settings, scaling or pagination can change the page).
    @MainActor static func savePDF(_ p: PersonalData, loc: Loc, includeJmbg: Bool = true) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "SuperCelik.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let view = makeView(p, includeJmbg: includeJmbg)
        let data = view.dataWithPDF(inside: view.bounds)
        do { try data.write(to: url, options: .atomic) } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
