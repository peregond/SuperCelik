import SwiftUI
import AppKit

// Palette: Serbian flag blue / red on system surfaces
let brandBlue = Color(red: 0.047, green: 0.251, blue: 0.463)
let brandRed = Color(red: 0.776, green: 0.212, blue: 0.235)

/// Accent colour: the brand navy in light mode, a lighter blue in dark mode where navy is unreadable.
let brandTint = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(srgbRed: 0.36, green: 0.62, blue: 0.96, alpha: 1)
        : NSColor(srgbRed: 0.047, green: 0.251, blue: 0.463, alpha: 1)
})

enum Page: String, Hashable { case personal, token, settings, about }

// MARK: - Reusable pieces

/// Content surface: a flat, softly rounded panel (the toolbar and sidebar carry the system glass).
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var icon: String?
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon) }
            Text(text).lineLimit(2)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// "Valid for N more days" / "Expired" pill, green > 90 days, orange <= 90, red when expired.
struct ExpiryPill: View {
    @EnvironmentObject var loc: Loc
    let date: Date
    var body: some View {
        let days = daysUntil(date)
        if days < 0 {
            Pill(text: loc.t(.expiredOn), color: .red, icon: "xmark.circle.fill")
        } else {
            Pill(text: String(format: loc.t(.expiresIn), days), color: days <= 90 ? .orange : .green,
                 icon: days <= 90 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        }
    }
}

struct CopyButton: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    let value: String
    @State private var done = false
    var body: some View {
        Button {
            model.copy(value)
            done = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { done = false }
        } label: {
            Image(systemName: done ? "checkmark" : "doc.on.doc").frame(width: 18, height: 18)
        }
        .buttonStyle(.plain).foregroundStyle(done ? Color.green : Color.secondary).help(loc.t(.copy))
    }
}

/// Centered placeholder for a page that has nothing to show yet.
struct EmptyState<Action: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var action: Action
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(brandTint)
                .frame(width: 96, height: 96)
                .background(Circle().fill(brandTint.opacity(0.12)))
            Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            action.padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Rounded, tinted notice shown above the page (update available, errors, notes).
struct Banner<Content: View>: View {
    let color: Color
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.25)))
            .padding(.horizontal, 20).padding(.top, 12)
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Prefs
    @SceneStorage("page") private var pageRaw = Page.personal.rawValue

    private var page: Page { Page(rawValue: pageRaw) ?? .personal }

    private var selection: Binding<Page?> {
        Binding(get: { page }, set: { if let v = $0 { pageRaw = v.rawValue } })
    }

    private var pageTitle: String {
        switch page {
        case .personal: return loc.t(.tabPersonal)
        case .token: return loc.t(.tabToken)
        case .settings: return loc.t(.tabSettings)
        case .about: return loc.t(.tabAbout)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 280)
        } detail: {
            VStack(spacing: 0) {
                updateBanner
                problemBanner
                Group {
                    switch page {
                    case .personal: PersonalView()
                    case .token: TokenView()
                    case .settings: SettingsView()
                    case .about: AboutView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(pageTitle)
        }
        .tint(brandTint)
        .sheet(isPresented: $model.showPreview) { PreviewSheet() }
        .task { await model.startMonitoring() }
        .task { if prefs.autoUpdate { await model.checkUpdates(manual: false) } }
        .task { await Shot.runIfRequested(setPage: { pageRaw = $0 }) }
    }

    private var sidebar: some View {
        List(selection: selection) {
            Section {
                Label(loc.t(.tabPersonal), systemImage: "person.text.rectangle").tag(Page.personal)
                Label(loc.t(.tabToken), systemImage: "key.viewfinder").tag(Page.token)
            }
            Section {
                Label(loc.t(.tabSettings), systemImage: "gearshape").tag(Page.settings)
                Label(loc.t(.tabAbout), systemImage: "info.circle").tag(Page.about)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(loc.t(.appTitle)).font(.headline)
                    Text(loc.t(.brandSub)).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { readerPanel }
    }

    /// Reader and card status, always visible at the bottom of the sidebar.
    private var readerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Group {
                    if model.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: model.cardPresent ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(model.cardPresent ? Color.green : Color.secondary)
                    }
                }
                .frame(width: 18, height: 18)
                Text(model.cardPresent ? loc.t(.cardPresent) : loc.t(.noCard))
                    .font(.callout.weight(.medium))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(loc.t(.refresh))
            }
            if model.readers.count > 1 {
                Picker(loc.t(.reader), selection: $model.selectedReader) {
                    ForEach(model.readers, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
            } else {
                Text(model.readers.first ?? loc.t(.noReader))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(10)
    }

    @ViewBuilder private var updateBanner: some View {
        if let u = model.update {
            Banner(color: brandTint) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill").font(.title3).foregroundStyle(brandTint)
                    Text(model.updating ? loc.t(.updateDownloading)
                                        : String(format: loc.t(.updateAvailable), u.version))
                        .fontWeight(.semibold)
                    Spacer()
                    if model.updating { ProgressView().controlSize(.small) }
                    Button(loc.t(.updateNow)) { Task { await model.installUpdate() } }
                        .buttonStyle(.borderedProminent).disabled(model.updating)
                }
            }
        }
    }

    @ViewBuilder private var problemBanner: some View {
        if let p = model.problem {
            Banner(color: p.isInfo ? Color.orange : Color.red) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: p.isInfo ? "info.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(p.isInfo ? Color.orange : Color.red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.titleKey.map { loc.t($0) } ?? p.raw).fontWeight(.semibold)
                        if let h = p.hintKey { Text(loc.t(h)).foregroundStyle(.secondary) }
                        if !p.tech.isEmpty {
                            Text("\(loc.t(.techDetails)): \(p.tech)").font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer()
                    Button { model.problem = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help(loc.t(.close))
                }
            }
        }
    }
}

// MARK: - Personal data

struct PersonalView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        Group {
            if let p = model.personal {
                ScrollView {
                    summary(p)
                    .padding(20)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                }
            } else {
                EmptyState(systemImage: "person.text.rectangle",
                           title: model.cardPresent ? loc.t(.cardPresent)
                                                    : (model.readers.isEmpty ? loc.t(.noReader) : loc.t(.noCard)),
                           message: loc.t(.hintRead)) {
                    VStack(spacing: 12) {
                        Button { Task { await model.readCard() } } label: {
                            Label(loc.t(.readCard), systemImage: "person.text.rectangle").fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!model.cardPresent || model.busy)
                        sigPill
                    }
                }
            }
        }
        .toolbar { actions }
    }

    // The system toolbar never truncates or wraps: actions that do not fit move into its own overflow menu.
    @ToolbarContentBuilder private var actions: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.showPreview = true } label: { Label(loc.t(.printCard), systemImage: "printer") }
                .disabled(model.personal == nil).help(loc.t(.printCard))
            Button { if let p = model.personal { Printer.savePDF(p, loc: loc, includeJmbg: prefs.printJmbg) } } label: {
                Label(loc.t(.savePdf), systemImage: "square.and.arrow.down")
            }
            .disabled(model.personal == nil).help(loc.t(.savePdf))
            Button { Task { await model.verifySignatures() } } label: {
                Label(loc.t(.verifySignature), systemImage: "checkmark.seal")
            }
            .disabled(!model.cardPresent || model.busy).help(loc.t(.verifySignature))
            if prefs.maskSensitive {
                // one eye for all sensitive fields: eye = hidden (click to show), crossed eye = shown (click to hide)
                Button { model.revealAll.toggle() } label: {
                    Label(model.revealAll ? loc.t(.hideValue) : loc.t(.reveal),
                          systemImage: model.revealAll ? "eye.slash" : "eye")
                }
                .disabled(model.personal == nil)
                .help(model.revealAll ? loc.t(.hideValue) : loc.t(.reveal))
            }
            Menu {
                Button { model.copyAll() } label: { Label(loc.t(.copyAll), systemImage: "doc.on.doc") }
                Button { model.savePhoto() } label: { Label(loc.t(.savePhoto), systemImage: "photo") }
                Button { model.exportJSON() } label: { Label(loc.t(.exportJson), systemImage: "curlybraces") }
            } label: { Label(loc.t(.more), systemImage: "ellipsis.circle") }
            .disabled(model.personal == nil).help(loc.t(.more))
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await model.readCard() } } label: {
                Label(loc.t(.readCard), systemImage: "person.text.rectangle")
            }
            .labelStyle(.titleAndIcon).buttonStyle(.borderedProminent)
            .disabled(!model.cardPresent || model.busy).help(loc.t(.readCard))
        }
    }

    /// Everything on one card, sized to fit the window without scrolling: photo on the left,
    /// name and all fields on the right.
    private func summary(_ p: PersonalData) -> some View {
        Card {
            HStack(alignment: .top, spacing: 20) {
                portrait(p)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(p.fixed.givenName) \(p.fixed.surname)")
                            .font(.system(size: 22, weight: .bold))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Text(docTypeName(p.cardType)).foregroundStyle(.secondary)
                            if let d = p.expiryDate { ExpiryPill(date: d) }
                        }
                        sigPill
                    }
                    Divider()
                    FieldGrid(rows: p.rows())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var sigPill: some View {
        switch model.signatureStatus {
        case .ok: Pill(text: loc.t(.sigOk), color: .green, icon: "checkmark.seal.fill")
        case .chainNotTrusted: Pill(text: loc.t(.sigChain), color: .orange, icon: "exclamationmark.triangle.fill")
        case .invalid: Pill(text: loc.t(.sigBad), color: .red, icon: "xmark.seal.fill")
        case .unavailable: Text(loc.t(.notImplemented)).font(.caption).foregroundStyle(.secondary)
        case nil: EmptyView()
        }
    }

    @ViewBuilder private func portrait(_ p: PersonalData) -> some View {
        Group {
            if let d = p.portrait, let img = NSImage(data: d) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "person.fill").resizable().scaledToFit().padding(34).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 150, height: 190)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private func docTypeName(_ t: EidCardType) -> String {
        switch t {
        case .if2020: return loc.t(.docIF)
        case .rp2024: return loc.t(.docRP)
        default: return loc.t(.docID)
        }
    }
}

/// Fields in as many columns as the window width allows.
struct FieldGrid: View {
    let rows: [Row]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16, alignment: .topLeading)],
                  alignment: .leading, spacing: 12) {
            ForEach(rows) { FieldCell(row: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One field: label + value. Sensitive values follow the global eye; the copy button appears on hover.
struct FieldCell: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Prefs
    let row: Row
    @State private var hovering = false

    private var masked: Bool { row.sensitive && prefs.maskSensitive }
    private var hidden: Bool { masked && !model.revealAll }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.t(row.label)).font(.caption).foregroundStyle(.secondary)
                Text(hidden ? "••••••••••" : row.value)
                    .font(.body.weight(.medium))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            CopyButton(value: row.value).opacity(hovering ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Token

struct TokenView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.tokenRows.isEmpty {
                EmptyState(systemImage: "key.viewfinder", title: loc.t(.certificates), message: loc.t(.hintToken)) {
                    VStack(spacing: 12) {
                        readButton.controlSize(.large)
                        Text(loc.t(.pinNote)).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 420)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let t = model.token {
                            HStack(spacing: 10) {
                                Image(systemName: "key.fill").foregroundStyle(brandTint)
                                Text(t.tokenLabel).font(.title3.weight(.semibold))
                                Text(t.tokenSerial).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        ForEach(model.tokenRows) { certificate($0) }
                        Text(loc.t(.pinNote)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                readButton.labelStyle(.titleAndIcon).help(loc.t(.readToken))
            }
        }
    }

    private var readButton: some View {
        Button { Task { await model.readToken() } } label: {
            Label(loc.t(.readToken), systemImage: "key")
        }
        .buttonStyle(.borderedProminent).disabled(!model.cardPresent || model.busy)
    }

    private func certificate(_ row: TokenCertRow) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Label(row.label.isEmpty ? (row.summary?.subject ?? "") : row.label, systemImage: "checkmark.seal")
                        .font(.headline)
                    Spacer()
                    if let s = row.summary {
                        Pill(text: s.chainTrusted ? loc.t(.chainOk) : loc.t(.sigChain),
                             color: s.chainTrusted ? .green : .orange,
                             icon: s.chainTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    }
                }
                if let s = row.summary {
                    if !s.issuer.isEmpty {
                        Text("\(loc.t(.certIssuer)): \(s.issuer)").foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if let a = s.notBefore, let b = s.notAfter {
                        HStack(spacing: 10) {
                            Text(String(format: loc.t(.certValid), a.formatted(date: .numeric, time: .omitted),
                                        b.formatted(date: .numeric, time: .omitted))).foregroundStyle(.secondary)
                            ExpiryPill(date: b)
                        }
                    }
                }
                Button { model.exportCertificate(row) } label: {
                    Label(loc.t(.exportCert), systemImage: "square.and.arrow.down")
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs

    var body: some View {
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
                LabeledContent(loc.t(.setAutoHide)) {
                    HStack(spacing: 6) {
                        Text("\(prefs.autoHideMinutes)").monospacedDigit()
                        Stepper(loc.t(.setAutoHide), value: $prefs.autoHideMinutes, in: 0...240).labelsHidden()
                    }
                }
            }
            Section(loc.t(.setBehavior)) {
                Toggle(loc.t(.setAutoRead), isOn: $prefs.autoRead)
                Toggle(loc.t(.setAutoUpdate), isOn: $prefs.autoUpdate)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - About

struct AboutView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            Text(loc.t(.appTitle)).font(.system(size: 30, weight: .bold))
            Text("\(loc.t(.version)) \(Updater.currentVersion)").foregroundStyle(.secondary)
            Text(loc.t(.aboutText)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 400).padding(.top, 6)
            Button { Task { await model.checkUpdates(manual: true) } } label: {
                Label(loc.t(.checkUpdates), systemImage: "arrow.triangle.2.circlepath")
            }
            .controlSize(.large).padding(.top, 10)
            if let s = model.updateStatus {
                Text(s).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Print preview

struct PreviewSheet: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        VStack(spacing: 14) {
            Text("\(loc.t(.preview)) — \(loc.t(.appTitle))").font(.headline)
            if let p = model.personal {
                ScrollView {
                    PrintSheet(p: p, loc: loc, includeJmbg: prefs.printJmbg)
                        .frame(width: 595, height: 842)
                        .scaleEffect(0.8, anchor: .topLeading)
                        .frame(width: 595 * 0.8, height: 842 * 0.8, alignment: .topLeading)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 2)
                        .padding(8)
                }
            }
            HStack {
                Spacer()
                Button { model.showPreview = false } label: { Label(loc.t(.close), systemImage: "xmark") }
                    .keyboardShortcut(.cancelAction)
                Button { if let p = model.personal { Printer.savePDF(p, loc: loc, includeJmbg: prefs.printJmbg) } } label: {
                    Label(loc.t(.savePdf), systemImage: "square.and.arrow.down")
                }
                Button { if let p = model.personal { Printer.print(p, loc: loc, includeJmbg: prefs.printJmbg) } } label: {
                    Label(loc.t(.printCard), systemImage: "printer").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 780)
    }
}
