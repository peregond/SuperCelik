import SwiftUI
import AppKit

/// A4 printout of the data read from the card (no PIN involved).
struct PrintSheet: View {
    let p: PersonalData
    let loc: Loc

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t(.appTitle)).font(.system(size: 20, weight: .bold))
            Divider()
            HStack(alignment: .top, spacing: 24) {
                Group {
                    if let d = p.portrait, let img = NSImage(data: d) {
                        Image(nsImage: img).resizable().scaledToFit()
                    } else { Color.clear }
                }.frame(width: 120, height: 150)
                VStack(alignment: .leading, spacing: 6) {
                    let f = p.fixed, d = p.document
                    line(.surname, f.surname); line(.givenName, f.givenName)
                    if !f.parentGivenName.isEmpty { line(.parentName, f.parentGivenName) }
                    line(.dob, f.dateOfBirth); line(.sex, f.sex)
                    line(.placeOfBirth, [f.placeOfBirth, f.communityOfBirth, f.stateOfBirth].filter { !$0.isEmpty }.joined(separator: ", "))
                    if !f.nationalityFull.isEmpty { line(.nationality, f.nationalityFull) }
                    line(.jmbg, f.personalNumber)
                    line(.address, p.variable.formatted)
                    Divider()
                    line(.docNumber, d.docRegNo)
                    if !d.documentSerialNumber.isEmpty { line(.docSerial, d.documentSerialNumber) }
                    line(.issuedBy, d.issuingAuthority)
                    line(.issueDate, d.issuingDate); line(.expiryDate, d.expiryDate)
                }
            }
            Spacer()
            Text(Date.now.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 595, height: 842, alignment: .topLeading)   // A4 @72dpi
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func line(_ k: Loc.L, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(loc.t(k)).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
            Text(v)
        }.font(.system(size: 12))
    }
}

enum Printer {
    /// Opens the standard macOS print dialog (which also offers "Save as PDF").
    @MainActor static func print(_ p: PersonalData, loc: Loc) {
        let host = NSHostingView(rootView: PrintSheet(p: p, loc: loc))
        host.frame = NSRect(x: 0, y: 0, width: 595, height: 842)
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        let op = NSPrintOperation(view: host, printInfo: info)
        op.showsPrintPanel = true
        op.run()
    }
}
