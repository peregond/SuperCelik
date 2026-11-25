import SwiftUI
import AppKit

/// Pieces for the vehicle registration card shown on the "Card data" page. STATUS: parsed per the specification,
/// not yet checked on a real card.
struct VehicleCell: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Prefs
    let key: String
    let value: String
    @State private var hovering = false

    private var hidden: Bool { (VehicleRows.sensitive.contains(key) || HealthRows.sensitive.contains(key)) && prefs.maskSensitive && !model.revealAll }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.x(key)).font(.caption).foregroundStyle(.secondary)
                Text(hidden ? "••••••••••" : value).font(.body.weight(.medium)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            CopyButton(value: value).opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
        .padding(.horizontal, -6).padding(.vertical, -4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Hidden card diagnostics (Settings, after 5 taps on the version): structure of the card, no personal data, no PIN.
struct DiagnosticsSection: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section(loc.x("diagTitle")) {
            Text(loc.x("diagText")).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(loc.x("diagRun")) { Task { await model.runDiagnostics() } }.disabled(!model.cardPresent || model.busy)
                Button(loc.x("diagCopy")) { model.copy(model.diagLog ?? ""); model.problem = Problem(raw: loc.x("diagCopied"), isInfo: true) }
                    .disabled(model.diagLog == nil)
            }
            if let log = model.diagLog {
                ScrollView([.vertical, .horizontal]) {
                    Text(log).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
            }
        }
    }
}
