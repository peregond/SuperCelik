import SwiftUI
import AppKit

// Palette: Serbian flag blue / red on system surfaces
let brandBlue = Color(red: 0.047, green: 0.251, blue: 0.463)
let brandRed = Color(red: 0.776, green: 0.212, blue: 0.235)

enum Page: String, Hashable { case personal, token, settings, about }

// MARK: - Reusable pieces

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 2)
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var icon: String?
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon) }
            Text(text).lineLimit(2)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.13)))
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
            Image(systemName: done ? "checkmark" : "doc.on.doc").frame(width: 18)
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).help(loc.t(.copy))
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Prefs
    @SceneStorage("page") private var pageRaw = Page.personal.rawValue

    private var selection: Binding<Page?> {
        Binding(get: { Page(rawValue: pageRaw) ?? .personal }, set: { if let v = $0 { pageRaw = v.rawValue } })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
        } detail: {
            VStack(spacing: 0) {
                updateBanner
                header
                if model.busy { ProgressView().progressViewStyle(.linear).tint(brandRed) }
                Divider()
                problemBanner
                Group {
                    switch Page(rawValue: pageRaw) ?? .personal {
                    case .personal: PersonalView()
                    case .token: TokenView()
                    case .settings: SettingsView()
                    case .about: AboutView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .tint(brandBlue)
        .sheet(isPresented: $model.showPreview) { PreviewSheet() }
        .task { await model.startMonitoring() }
        .task { if prefs.autoUpdate { await model.checkUpdates(manual: false) } }
        .task { await Shot.runIfRequested(setPage: { pageRaw = $0 }) }
    }

    private var sidebar: some View {
        List(selection: selection) {
            Label(loc.t(.tabPersonal), systemImage: "person.text.rectangle").tag(Page.personal)
            Label(loc.t(.tabToken), systemImage: "key.viewfinder").tag(Page.token)
            Label(loc.t(.tabSettings), systemImage: "gearshape").tag(Page.settings)
            Label(loc.t(.tabAbout), systemImage: "info.circle").tag(Page.about)
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(loc.t(.appTitle)).font(.system(size: 16, weight: .bold))
                    Text(loc.t(.brandSub)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Text("\(loc.t(.version)) \(Updater.currentVersion)")
                .font(.caption).foregroundStyle(.secondary).padding(10)
        }
    }

    @ViewBuilder private var updateBanner: some View {
        if let u = model.update {
            HStack {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(brandBlue)
                Text(model.updating ? loc.t(.updateDownloading)
                                    : String(format: loc.t(.updateAvailable), u.version))
                    .fontWeight(.semibold)
                Spacer()
                Button { Task { await model.installUpdate() } } label: { Label(loc.t(.updateNow), systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent).disabled(model.updating)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(Color.yellow.opacity(0.18))
        }
    }

    @ViewBuilder private var problemBanner: some View {
        if let p = model.problem {
            HStack(alignment: .top) {
                Image(systemName: p.isInfo ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(p.isInfo ? Color.secondary : Color.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.titleKey.map { loc.t($0) } ?? p.raw).fontWeight(.bold)
                        .foregroundStyle(p.isInfo ? Color.primary : Color.red)
                    if let h = p.hintKey { Text(loc.t(h)) }
                    if !p.tech.isEmpty {
                        Text("\(loc.t(.techDetails)): \(p.tech)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { model.problem = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(loc.t(.close))
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background((p.isInfo ? Color.yellow : Color.red).opacity(0.12))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.selectedReader) {
                if model.readers.isEmpty { Text(loc.t(.noReader)).tag("") }
                ForEach(model.readers, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(maxWidth: 260)
            Button { model.refresh() } label: { Label(loc.t(.refresh), systemImage: "arrow.clockwise") }
            Pill(text: model.cardPresent ? loc.t(.cardPresent) : loc.t(.noCard),
                 color: model.cardPresent ? .green : .secondary,
                 icon: model.cardPresent ? "checkmark.circle.fill" : "xmark.circle")
            Spacer()
        }
        .controlSize(.large)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Personal data

struct PersonalView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                actionBar

                if let p = model.personal {
                    HStack(alignment: .top, spacing: 18) {
                        Card {
                            VStack(spacing: 12) {
                                portrait(p)
                                Text("\(p.fixed.givenName) \(p.fixed.surname)")
                                    .font(.system(size: 17, weight: .bold)).multilineTextAlignment(.center)
                                Text(docTypeName(p.cardType)).foregroundStyle(.secondary)
                                if let d = p.expiryDate { ExpiryPill(date: d) }
                            }
                            .frame(width: 190)
                        }
                        Card {
                            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                                GridItem(.flexible(), alignment: .topLeading)],
                                      alignment: .leading, spacing: 16) {
                                ForEach(p.rows()) { row in FieldCell(row: row) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84).opacity(0.9)
                        Text(loc.t(.hintRead)).font(.system(size: 14)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 420)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(24)
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
            Button { Task { await model.readCard() } } label: {
                Label(loc.t(.readCard), systemImage: "person.text.rectangle").fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!model.cardPresent || model.busy).keyboardShortcut("r")
            Button { model.showPreview = true } label: { Label(loc.t(.printCard), systemImage: "printer") }
                .controlSize(.large).disabled(model.personal == nil).keyboardShortcut("p")
            Button { if let p = model.personal { Printer.savePDF(p, loc: loc, includeJmbg: prefs.printJmbg) } } label: {
                Label(loc.t(.savePdf), systemImage: "square.and.arrow.down")
            }
            .controlSize(.large).disabled(model.personal == nil).keyboardShortcut("s")
            Button { Task { await model.verifySignatures() } } label: {
                Label(loc.t(.verifySignature), systemImage: "checkmark.seal")
            }
            .controlSize(.large).disabled(!model.cardPresent || model.busy)
            if prefs.maskSensitive {
                // one eye for all sensitive fields: eye = hidden (click to show), crossed eye = shown (click to hide)
                Button { model.revealAll.toggle() } label: {
                    Label(model.revealAll ? loc.t(.hideValue) : loc.t(.reveal), systemImage: model.revealAll ? "eye.slash" : "eye")
                }
                .controlSize(.large).disabled(model.personal == nil)
            }
            Menu {
                Button { model.copyAll() } label: { Label(loc.t(.copyAll), systemImage: "doc.on.doc") }
                Button { model.savePhoto() } label: { Label(loc.t(.savePhoto), systemImage: "photo") }
                Button { model.exportJSON() } label: { Label(loc.t(.exportJson), systemImage: "curlybraces") }
            } label: { Label(loc.t(.more), systemImage: "ellipsis.circle") }
            .controlSize(.large).disabled(model.personal == nil).fixedSize()
            Spacer()
        }
        sigPill
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
                Image(systemName: "person.crop.rectangle").resizable().scaledToFit().padding(40).foregroundStyle(.secondary)
            }
        }
        .frame(width: 170, height: 215)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func docTypeName(_ t: EidCardType) -> String {
        switch t {
        case .if2020: return loc.t(.docIF)
        case .rp2024: return loc.t(.docRP)
        default: return loc.t(.docID)
        }
    }
}

/// One field: label + value, with a reveal toggle for sensitive values and a copy button.
struct FieldCell: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Prefs
    let row: Row

    private var masked: Bool { row.sensitive && prefs.maskSensitive }
    private var hidden: Bool { masked && !model.revealAll }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t(row.label)).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(hidden ? "••••••••••" : row.value).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
            }
            Spacer(minLength: 4)
            CopyButton(value: row.value)
        }
    }
}

// MARK: - Token

struct TokenView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { Task { await model.readToken() } } label: {
                        Label(loc.t(.readToken), systemImage: "key").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.cardPresent || model.busy)
                    if let t = model.token {
                        Text("\(t.tokenLabel)  \(t.tokenSerial)").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(loc.t(.certificates)).font(.system(size: 15, weight: .bold))
                        if model.tokenRows.isEmpty {
                            Text(loc.t(.hintToken)).foregroundStyle(.secondary)
                        }
                        ForEach(model.tokenRows) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(row.label.isEmpty ? (row.summary?.subject ?? "") : row.label)
                                        .font(.system(size: 14, weight: .semibold))
                                    Spacer()
                                    if let s = row.summary {
                                        Pill(text: s.chainTrusted ? loc.t(.chainOk) : loc.t(.sigChain),
                                             color: s.chainTrusted ? .green : .orange,
                                             icon: s.chainTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    }
                                }
                                if let s = row.summary {
                                    if !s.issuer.isEmpty {
                                        Text("\(loc.t(.certIssuer)): \(s.issuer)").foregroundStyle(.secondary)
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
                                Divider().padding(.top, 6)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(loc.t(.pinNote)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(loc.t(.setAppearance)).font(.system(size: 15, weight: .bold))
                        HStack {
                            Text(loc.t(.language))
                            Spacer()
                            Picker("", selection: $loc.language) {
                                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.segmented).frame(width: 260)
                        }
                        HStack {
                            Text(loc.t(.setTheme))
                            Spacer()
                            Picker("", selection: $prefs.theme) {
                                Text(loc.t(.themeSystem)).tag("system")
                                Text(loc.t(.themeLight)).tag("light")
                                Text(loc.t(.themeDark)).tag("dark")
                            }
                            .labelsHidden().pickerStyle(.segmented).frame(width: 260)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(loc.t(.setPrivacy)).font(.system(size: 15, weight: .bold))
                        Toggle(loc.t(.setMask), isOn: $prefs.maskSensitive)
                        Toggle(loc.t(.setPrintJmbg), isOn: $prefs.printJmbg)
                        HStack {
                            Text(loc.t(.setAutoHide))
                            Spacer()
                            TextField("", value: $prefs.autoHideMinutes, format: .number)
                                .multilineTextAlignment(.center).frame(width: 60)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(loc.t(.setBehavior)).font(.system(size: 15, weight: .bold))
                        Toggle(loc.t(.setAutoRead), isOn: $prefs.autoRead)
                        Toggle(loc.t(.setAutoUpdate), isOn: $prefs.autoUpdate)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - About

struct AboutView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                Text(loc.t(.appTitle)).font(.system(size: 26, weight: .bold))
                Text(loc.t(.aboutText)).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
                Text("\(loc.t(.version)) \(Updater.currentVersion)").fontWeight(.semibold).padding(.top, 8)
                Button { Task { await model.checkUpdates(manual: true) } } label: {
                    Label(loc.t(.checkUpdates), systemImage: "arrow.triangle.2.circlepath")
                }
                if let s = model.updateStatus {
                    Text(s).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
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
                        .scaleEffect(0.8, anchor: .topLeading)
                        .frame(width: 595 * 0.8, height: 842 * 0.8, alignment: .topLeading)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 2)
                        .padding(8)
                }
            }
            HStack {
                Spacer()
                Button { model.showPreview = false } label: { Label(loc.t(.close), systemImage: "xmark") }
                Button { if let p = model.personal { Printer.savePDF(p, loc: loc, includeJmbg: prefs.printJmbg) } } label: {
                    Label(loc.t(.savePdf), systemImage: "square.and.arrow.down")
                }
                Button { if let p = model.personal { Printer.print(p, loc: loc, includeJmbg: prefs.printJmbg) } } label: {
                    Label(loc.t(.printCard), systemImage: "printer").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560, height: 780)
    }
}
