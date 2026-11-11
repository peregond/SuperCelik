import SwiftUI
import UIKit

struct PhoneRootView: View {
    @EnvironmentObject var loc: Loc

    var body: some View {
        TabView {
            CardTab()
                .tabItem { Label(loc.t(.tabPersonal), systemImage: "person.text.rectangle") }
            TokenTab()
                .tabItem { Label(loc.t(.tabToken), systemImage: "checkmark.seal") }
            SettingsTab()
                .tabItem { Label(loc.t(.tabSettings), systemImage: "gearshape") }
        }
    }
}

// MARK: - Shared pieces

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIActivityViewController for a file (PDF / certificate).
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ProblemBanner: View {
    @EnvironmentObject var loc: Loc
    let problem: PhoneProblem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(loc.t(problem.title), systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text(loc.t(problem.hint)).font(.subheadline)
            if !problem.tech.isEmpty {
                Text(problem.tech).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ScanButton: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: PhoneModel
    let title: Loc.L
    var icon = "cable.connector"
    var primary = true
    var needsNfc = false
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if model.busy { ProgressView() } else { Image(systemName: icon) }
                Text(loc.t(title)).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(primary ? .accentColor : .gray)
        .disabled(model.busy || (needsNfc && !model.nfcAvailable))
    }
}

// MARK: - Card

struct CardTab: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: PhoneModel
    @State private var share: ShareItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Wired reader is the main way; NFC is for cards that have a contactless chip.
                    ScanButton(title: .scanUsb) { await model.scanCard(.usb) }
                    ScanButton(title: .scanCard, icon: "wave.3.right", primary: false, needsNfc: true) { await model.scanCard(.nfc) }
                    if let problem = model.problem {
                        ProblemBanner(problem: problem)
                    } else if model.personal == nil {
                        Text(loc.t(.hintUsb)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let p = model.personal {
                    Section { header(p) }
                    if let s = model.signatureStatus { Section { signatureRow(s) } }
                    Section {
                        ForEach(p.rows(includeJmbg: true)) { row in FieldRow(row: row) }
                    }
                    Section {
                        Button { model.printPDF(includeJmbg: prefs.printJmbg) } label: {
                            Label(loc.t(.printCard), systemImage: "printer")
                        }
                        Button {
                            if let url = model.pdfFile(includeJmbg: prefs.printJmbg) { share = ShareItem(url: url) }
                        } label: { Label(loc.t(.sharePdf), systemImage: "square.and.arrow.up") }
                        Button { model.copyAll() } label: { Label(loc.t(.copyAll), systemImage: "doc.on.doc") }
                    }
                }
            }
            .navigationTitle(loc.t(.appTitle))
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if model.personal != nil {
                        Button { model.revealAll.toggle() } label: {
                            Image(systemName: model.revealAll ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(loc.t(model.revealAll ? .hideValue : .reveal))
                    }
                }
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if model.personal != nil {
                        Button(role: .destructive) { model.clear() } label: { Image(systemName: "trash") }
                            .accessibilityLabel(loc.t(.close))
                    }
                }
            }
            .sheet(item: $share) { ShareSheet(url: $0.url) }
        }
    }

    private func header(_ p: PersonalData) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let d = p.portrait, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(width: 96, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(docTitle(p.cardType)).font(.caption).foregroundStyle(.secondary)
                Text("\(p.fixed.givenName) \(p.fixed.surname)").font(.title3.bold())
                if let exp = p.expiryDate { expiry(exp) }
            }
        }
        .padding(.vertical, 4)
    }

    private func expiry(_ date: Date) -> some View {
        let days = daysUntil(date)
        return Group {
            if days < 0 {
                Label(loc.t(.expiredOn), systemImage: "xmark.circle.fill").foregroundStyle(.red)
            } else {
                Label(String(format: loc.t(.expiresIn), days), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(days <= 90 ? Color.orange : Color.green)
            }
        }
        .font(.caption)
    }

    private func docTitle(_ t: EidCardType) -> String {
        switch t {
        case .if2020: return loc.t(.docIF)
        case .rp2024: return loc.t(.docRP)
        default: return loc.t(.docID)
        }
    }

    @ViewBuilder private func signatureRow(_ s: PhoneModel.SigStatus) -> some View {
        switch s {
        case .ok:
            Label(loc.t(.sigOk), systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case .chainNotTrusted(let m):
            VStack(alignment: .leading, spacing: 4) {
                Label(loc.t(.sigChain), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(m).font(.caption).foregroundStyle(.secondary)
            }
        case .invalid(let m):
            VStack(alignment: .leading, spacing: 4) {
                Label(loc.t(.sigBad), systemImage: "xmark.seal.fill").foregroundStyle(.red)
                Text(m).font(.caption).foregroundStyle(.secondary)
            }
        case .unavailable:
            EmptyView()
        }
    }
}

struct FieldRow: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: PhoneModel
    let row: Row

    private var hidden: Bool { row.sensitive && prefs.maskSensitive && !model.revealAll }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(loc.t(row.label)).font(.caption).foregroundStyle(.secondary)
            Text(hidden ? "••••••••••" : (row.value.isEmpty ? "—" : row.value))
                .font(.body.weight(.medium))
                .textSelection(.enabled)
        }
        .contextMenu {
            Button { UIPasteboard.general.string = row.value } label: { Label(loc.t(.copy), systemImage: "doc.on.doc") }
        }
    }
}

// MARK: - Token / certificates

struct TokenTab: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: PhoneModel
    @State private var share: ShareItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScanButton(title: .readToken) { await model.scanToken(.usb) }
                    if let problem = model.problem, model.token == nil {
                        ProblemBanner(problem: problem)
                    }
                    Text(loc.t(.pinNote)).font(.footnote).foregroundStyle(.secondary)
                }
                if let t = model.token {
                    Section {
                        if !t.tokenLabel.isEmpty { LabeledContent("Token", value: t.tokenLabel) }
                        if !t.tokenSerial.isEmpty { LabeledContent("Serial", value: t.tokenSerial) }
                    }
                    Section(loc.t(.certificates)) {
                        ForEach(model.tokenRows) { row in certificate(row) }
                    }
                }
            }
            .navigationTitle(loc.t(.tabToken))
            .sheet(item: $share) { ShareSheet(url: $0.url) }
        }
    }

    private func certificate(_ row: PhoneCertRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.summary?.subject ?? row.label).font(.headline)
            if !row.label.isEmpty { Text(row.label).font(.caption).foregroundStyle(.secondary) }
            if let s = row.summary {
                if !s.issuer.isEmpty { Text("\(loc.t(.certIssuer)): \(s.issuer)").font(.subheadline) }
                if let a = s.notBefore, let b = s.notAfter {
                    Text(String(format: loc.t(.certValid), a.formatted(date: .numeric, time: .omitted),
                                b.formatted(date: .numeric, time: .omitted))).font(.subheadline)
                }
                if s.chainTrusted {
                    Label(loc.t(.chainOk), systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.subheadline)
                } else {
                    Label(loc.t(.sigChain), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.subheadline)
                }
            }
            Button {
                if let url = model.temporaryFile(row.der, name: "certificate.cer") { share = ShareItem(url: url) }
            } label: { Label(loc.t(.exportCert), systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings / about

struct SettingsTab: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(loc.t(.setAppearance)) {
                    Picker(loc.t(.language), selection: $loc.language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(loc.t(.setTheme), selection: $prefs.theme) {
                        Text(loc.t(.themeSystem)).tag("system")
                        Text(loc.t(.themeLight)).tag("light")
                        Text(loc.t(.themeDark)).tag("dark")
                    }
                }
                Section(loc.t(.setPrivacy)) {
                    Toggle(loc.t(.setMask), isOn: $prefs.maskSensitive)
                    Toggle(loc.t(.setPrintJmbg), isOn: $prefs.printJmbg)
                }
                Section(loc.t(.tabAbout)) {
                    Text(loc.t(.aboutTextIOS)).font(.subheadline)
                    LabeledContent(loc.t(.version), value: version)
                    Link("github.com/peregond/SuperCelik", destination: URL(string: "https://github.com/peregond/SuperCelik")!)
                }
            }
            .navigationTitle(loc.t(.tabSettings))
        }
    }
}
