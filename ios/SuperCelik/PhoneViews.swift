import SwiftUI
import UIKit

struct PhoneRootView: View {
    @EnvironmentObject var loc: Loc
    @State private var showSettings = false

    var body: some View {
        tabs
            .minimizingTabBar()
            .sheet(isPresented: $showSettings) { SettingsTab() }
    }

    /// iPhone: tab bar (Liquid Glass). iPad: iOS 18+ turns the same tabs into a sidebar like the Mac app.
    @ViewBuilder private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView {
                Tab(loc.t(.tabPersonal), systemImage: "person.text.rectangle") { CardTab(showSettings: $showSettings) }
                Tab(loc.t(.tabToken), systemImage: "checkmark.seal") { TokenTab(showSettings: $showSettings) }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView {
                CardTab(showSettings: $showSettings)
                    .tabItem { Label(loc.t(.tabPersonal), systemImage: "person.text.rectangle") }
                TokenTab(showSettings: $showSettings)
                    .tabItem { Label(loc.t(.tabToken), systemImage: "checkmark.seal") }
            }
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

/// The one main button: the app picks the wired reader if one is connected, otherwise NFC.
struct ScanButton: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: PhoneModel
    let title: Loc.L
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if model.busy { ProgressView() } else { Image(systemName: model.autoIcon) }
                Text(loc.t(title)).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .glassButton(prominent: true)
        .tint(.blue)
        .controlSize(.large)
        .disabled(model.busy)
    }
}

/// Settings gear in the top-right corner of every screen.
struct SettingsButton: View {
    @EnvironmentObject var loc: Loc
    @Binding var show: Bool
    var body: some View {
        Button { show = true } label: { Image(systemName: "gearshape") }
            .accessibilityLabel(loc.t(.tabSettings))
    }
}

// MARK: - Card

struct CardTab: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: PhoneModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var showSettings: Bool
    @State private var share: ShareItem?
    @State private var pdf: ShareItem?
    @State private var photoOpen = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let problem = model.problem {
                        ProblemBanner(problem: problem).padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                    } else if model.personal == nil {
                        Text(loc.t(.hintAuto)).font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal).padding(.top, 40)
                    }
                    if let p = model.personal {
                        if sizeClass == .regular { regularLayout(p) } else { compactLayout(p) }
                    }
                }
                .padding(16)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(GlassBackdrop())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                ScanButton(title: .readCardAuto) { await model.scanCardAuto() }
                    .padding(.horizontal, 20).padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if model.personal != nil {
                        Button { model.revealAll.toggle() } label: {
                            Image(systemName: model.revealAll ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(loc.t(model.revealAll ? .hideValue : .reveal))
                    }
                    SettingsButton(show: $showSettings)
                }
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if model.personal != nil {
                        Button(role: .destructive) { model.clear() } label: { Image(systemName: "trash") }
                            .accessibilityLabel(loc.t(.close))
                    }
                }
            }
            .sheet(item: $share) { ShareSheet(url: $0.url) }
            .sheet(item: $pdf) { PDFPreview(url: $0.url).ignoresSafeArea() }
            .sheet(isPresented: $photoOpen) {
                if let d = model.personal?.portrait, let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFit().padding().presentationDetents([.medium, .large])
                }
            }
            .task {
                // screenshots only: `--pdf` opens the printout right away
                if CommandLine.arguments.contains("--pdf"), model.personal != nil,
                   let url = model.pdfFile(includeJmbg: prefs.printJmbg) { pdf = ShareItem(url: url) }
            }
        }
    }

    /// iPhone: one column.
    @ViewBuilder private func compactLayout(_ p: PersonalData) -> some View {
        header(p).padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
        if let s = model.signatureStatus {
            signatureRow(s).padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(cornerRadius: 22)
        }
        fieldsCard(p, columns: 1)
        actions
    }

    /// iPad: like the Mac window: name, signature and actions on the left, all fields on the right, one screen.
    @ViewBuilder private func regularLayout(_ p: PersonalData) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                header(p).padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                if let s = model.signatureStatus {
                    signatureRow(s).padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(cornerRadius: 22)
                }
                actions
            }
            .frame(width: 380)
            fieldsCard(p, columns: 2)
        }
    }

    private func fieldsCard(_ p: PersonalData, columns: Int) -> some View {
        let rows = p.rows(includeJmbg: true)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: columns), alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                FieldRow(row: row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .padding(.vertical, 6)
        .glassCard()
    }

    private var actions: some View {
        GlassGroup(spacing: 10) {
            Button { if let url = model.pdfFile(includeJmbg: prefs.printJmbg) { pdf = ShareItem(url: url) } } label: {
                Label(loc.t(.viewPdf), systemImage: "doc.richtext").frame(maxWidth: .infinity).padding(.vertical, 6)
            }.glassButton(prominent: false)
            HStack(spacing: 10) {
                Button { model.printPDF(includeJmbg: prefs.printJmbg) } label: {
                    Label(loc.t(.printCard), systemImage: "printer").frame(maxWidth: .infinity).padding(.vertical, 6)
                }.glassButton(prominent: false)
                Button {
                    if let url = model.pdfFile(includeJmbg: prefs.printJmbg) { share = ShareItem(url: url) }
                } label: { Label(loc.t(.sharePdf), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 6) }
                    .glassButton(prominent: false)
            }
            Button { model.copyAll() } label: {
                Label(loc.t(.copyAll), systemImage: "doc.on.doc").frame(maxWidth: .infinity).padding(.vertical, 6)
            }.glassButton(prominent: false)
        }
    }

    private func header(_ p: PersonalData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FlagStripe()
            HStack(alignment: .top, spacing: 14) {
                if let d = p.portrait, let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 104, height: 136)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture { photoOpen = true }
                        .accessibilityLabel(loc.t(.photo))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(docTitle(p.cardType)).font(.caption).foregroundStyle(.secondary)
                    Text("\(p.fixed.givenName) \(p.fixed.surname)").font(.title3.bold())
                    if let exp = p.expiryDate { expiry(exp) }
                }
            }
        }
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
    @Binding var showSettings: Bool
    @State private var share: ShareItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
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
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                ScanButton(title: .readToken) { await model.scanTokenAuto() }
                    .padding(.horizontal, 20).padding(.bottom, 8)
            }
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { SettingsButton(show: $showSettings) } }
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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: PhoneModel
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
                Section {
                    Button(loc.t(.demoData)) { model.loadDemo(); dismiss() }
                } footer: { Text(loc.t(.demoHint)) }
                Section(loc.t(.tabAbout)) {
                    Text(loc.t(.aboutTextIOS)).font(.subheadline)
                    LabeledContent(loc.t(.version), value: version)
                    Link("github.com/peregond/SuperCelik", destination: URL(string: "https://github.com/peregond/SuperCelik")!)
                }
            }
            .navigationTitle(loc.t(.tabSettings))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(loc.t(.ok)) { dismiss() } } }
        }
    }
}
