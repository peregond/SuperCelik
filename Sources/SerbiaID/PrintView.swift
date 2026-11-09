import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A4 printout of the data read from the card (no PIN involved).
struct PrintSheet: View {
    let p: PersonalData
    let loc: Loc
    var includeJmbg: Bool = true

    private var docType: String {
        switch p.cardType {
        case .if2020: return loc.t(.docIF)
        case .rp2024: return loc.t(.docRP)
        default: return loc.t(.docID)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // flag-colored strip: red / blue / light grey
            HStack(spacing: 0) {
                Color(red: 0.776, green: 0.212, blue: 0.235)
                Color(red: 0.047, green: 0.251, blue: 0.463)
                Color(red: 0.89, green: 0.906, blue: 0.933)
            }.frame(height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(docType).font(.system(size: 22, weight: .bold)).foregroundStyle(Color(red: 0.047, green: 0.251, blue: 0.463))
                Text("\(p.fixed.givenName) \(p.fixed.surname)").font(.system(size: 15)).foregroundStyle(.gray)
                Spacer().frame(height: 18)
                HStack(alignment: .top, spacing: 28) {
                    if let d = p.portrait, let img = NSImage(data: d) {
                        Image(nsImage: img).resizable().scaledToFill().frame(width: 130, height: 165).clipped()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(p.rows(includeJmbg: includeJmbg)) { row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(loc.t(row.label)).foregroundStyle(.gray).frame(width: 150, alignment: .leading)
                                Text(row.value).fontWeight(.semibold).foregroundStyle(.black)
                            }.font(.system(size: 12))
                        }
                    }
                }
                Spacer()
                Text("Super Celik · \(Date.now.formatted(date: .numeric, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(.gray)
            }
            .padding(.horizontal, 48).padding(.vertical, 36)
        }
        .frame(width: 595, height: 842, alignment: .topLeading)   // A4 @72dpi
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

enum Printer {
    @MainActor private static func makeView(_ p: PersonalData, loc: Loc, includeJmbg: Bool) -> NSView {
        let host = NSHostingView(rootView: PrintSheet(p: p, loc: loc, includeJmbg: includeJmbg))
        host.frame = NSRect(x: 0, y: 0, width: 595, height: 842)
        return host
    }

    private static func baseInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        return info
    }

    /// Opens the standard macOS print dialog.
    @MainActor static func print(_ p: PersonalData, loc: Loc, includeJmbg: Bool = true) {
        let op = NSPrintOperation(view: makeView(p, loc: loc, includeJmbg: includeJmbg), printInfo: baseInfo())
        op.showsPrintPanel = true
        op.run()
    }

    /// Asks for a file name and writes a vector PDF directly (no print dialog).
    @MainActor static func savePDF(_ p: PersonalData, loc: Loc, includeJmbg: Bool = true) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "SuperCelik.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let info = baseInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let op = NSPrintOperation(view: makeView(p, loc: loc, includeJmbg: includeJmbg), printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.run()
    }
}
