import SwiftUI
import UIKit

/// A vehicle registration card on the "Card" tab (wired reader only: the NFC application name is not confirmed, so it
/// is not listed in Info.plist). STATUS: parsed per the specification, not yet checked on a real card.
struct VehicleCardView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: PhoneModel
    let vehicle: VehicleData
    @State private var pdf: ShareItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.x("vehTitle")).foregroundStyle(.secondary)
                Text(vehicle.registrationNumber).font(.title2.weight(.bold)).textSelection(.enabled)
            }
            // three groups in the order of the printout of MUP's reader: document, owner and user, vehicle
            ForEach(VehicleRows.sections(vehicle).filter { !$0.rows.filter { $0.key != "vRegNo" }.isEmpty }, id: \.title) { sec in
                Text(loc.x(sec.title)).font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .topLeading)], alignment: .leading, spacing: 14) {
                    ForEach(sec.rows.filter { $0.key != "vRegNo" }, id: \.key) { VehicleField(key: $0.key, value: $0.value) }
                }
            }
            Text(loc.x("vehNote")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { if let url = model.pdfFile(includeJmbg: prefs.printJmbg) { pdf = ShareItem(url: url) } } label: {
                    Label(loc.t(.viewPdf), systemImage: "doc.richtext").frame(maxWidth: .infinity).padding(.vertical, 6)
                }.glassButton(prominent: false)
                Button { model.printPDF(includeJmbg: prefs.printJmbg) } label: {
                    Label(loc.t(.printCard), systemImage: "printer").frame(maxWidth: .infinity).padding(.vertical, 6)
                }.glassButton(prominent: false)
            }
        }
        .sheet(item: $pdf) { PDFPreview(url: $0.url) }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

/// A health insurance card on the "Card" tab (wired reader only: the NFC applet name is not in Info.plist). No printout yet.
/// STATUS: read per the analysis of the official reader, not yet checked on a real card.
struct HealthCardView: View {
    @EnvironmentObject var loc: Loc
    let health: HealthData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.x("hTitle")).foregroundStyle(.secondary)
                Text(health.fullName).font(.title2.weight(.bold)).textSelection(.enabled)
            }
            ForEach(HealthRows.sections(health).filter { !$0.rows.isEmpty }, id: \.title) { sec in
                Text(loc.x(sec.title)).font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .topLeading)], alignment: .leading, spacing: 14) {
                    ForEach(sec.rows, id: \.key) { VehicleField(key: $0.key, value: $0.value) }
                }
            }
            Text(loc.x("hNote")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

struct VehicleField: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: PhoneModel
    let key: String
    let value: String

    private var hidden: Bool { (VehicleRows.sensitive.contains(key) || HealthRows.sensitive.contains(key)) && prefs.maskSensitive && !model.revealAll }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(loc.x(key)).font(.caption).foregroundStyle(.secondary)
            Text(hidden ? "••••••••••" : value).font(.body.weight(.medium)).textSelection(.enabled)
        }
        .contextMenu {
            Button { UIPasteboard.general.string = value } label: { Label(loc.t(.copy), systemImage: "doc.on.doc") }
        }
    }
}

/// Hidden card diagnostics (Settings, after 5 taps on the version): structure of the card, no personal data, no PIN.
struct DiagnosticsSection: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: PhoneModel

    var body: some View {
        Section(loc.x("diagTitle")) {
            Text(loc.x("diagText")).font(.subheadline).foregroundStyle(.secondary)
            Button(loc.x("diagRun")) { Task { await model.runDiagnostics() } }.disabled(model.busy)
            Button(loc.x("diagCopy")) { UIPasteboard.general.string = model.diagLog ?? "" }.disabled(model.diagLog == nil)
            if let log = model.diagLog {
                ScrollView([.vertical, .horizontal]) {
                    Text(log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 240)
            }
        }
        .listRowBackground(Rectangle().fill(.regularMaterial))
    }
}
