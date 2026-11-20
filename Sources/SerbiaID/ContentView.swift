import SwiftUI
import AppKit

// Palette: Serbian flag blue / red on system surfaces
let brandBlue = Color(red: 0.047, green: 0.251, blue: 0.463)
let brandRed = Color(red: 0.776, green: 0.212, blue: 0.235)

/// Accent colour: the red of the Serbian flag in light mode, a lighter red in dark mode where it reads better.
let brandTint = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(srgbRed: 0.94, green: 0.39, blue: 0.42, alpha: 1)
        : NSColor(srgbRed: 0.776, green: 0.212, blue: 0.235, alpha: 1)
})

enum Page: String, Hashable { case personal, token, settings }

/// One row of the sidebar: flag red when selected, a soft highlight on hover.
struct SidebarRow: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .fontWeight(selected ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? brandRed : Color.primary.opacity(hovering ? 0.07 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Reusable pieces

extension View {
    /// Liquid Glass button (macOS 26); a capsule bordered button before. Compiles with older Xcode too.
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass).tint(nil) }
        } else {
            self.bordered(prominent)
        }
        #else
        self.bordered(prominent)
        #endif
    }

    @ViewBuilder private func bordered(_ prominent: Bool) -> some View {
        let base = Group { if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) } }
        if #available(macOS 14.0, *) { base.buttonBorderShape(.capsule) } else { base }
    }

    /// Liquid Glass surface (macOS 26); the flat tinted panel before.
    @ViewBuilder func glassSurface(cornerRadius: CGFloat = 20) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.flatSurface(cornerRadius)
        }
        #else
        self.flatSurface(cornerRadius)
        #endif
    }

    private func flatSurface(_ r: CGFloat) -> some View {
        self.background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

/// One action of a page: a full-width glass capsule with an icon, the same everywhere.
struct ActionButton: View {
    let title: String
    let icon: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .glassButton(prominent: prominent).controlSize(.large)
    }
}

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

/// The Card and Token screens: a Liquid Glass panel (the flat one before macOS 26).
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .glassSurface()
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
            Image(systemName: done ? "checkmark" : "doc.on.doc").symbolReplace().frame(width: 18, height: 18)
        }
        .buttonStyle(.plain).foregroundStyle(done ? Color.green : Color.secondary).help(loc.t(.copy))
    }
}

extension View {
    /// SF Symbol swaps (copy -> check, eye -> crossed eye) morph on macOS 14+, and simply switch before.
    @ViewBuilder func symbolReplace() -> some View {
        if #available(macOS 14.0, *) { self.contentTransition(.symbolEffect(.replace)) } else { self }
    }
}

extension AnyTransition {
    /// Result pills pop in.
    static var pop: AnyTransition { .scale(scale: 0.8).combined(with: .opacity) }
}

/// Centered placeholder for a page that has nothing to show yet.
struct EmptyState<Icon: View, Action: View>: View {
    let title: String
    let message: String
    @ViewBuilder var icon: Icon
    @ViewBuilder var action: Action
    var body: some View {
        VStack(spacing: 14) {
            icon
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

    /// `--shot` asks for a page; SceneStorage does not work outside a scene, so it is kept here.
    @State private var shotPage: String? = Shot.page
    private var page: Page { Page(rawValue: shotPage ?? pageRaw) ?? .personal }

    private var pageTitle: String {
        switch page {
        case .personal: return loc.t(.tabPersonal)
        case .token: return loc.t(.tabToken)
        case .settings: return loc.t(.tabSettings)
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
                    .animation(.easeInOut(duration: 0.22), value: model.problem == nil)
                Group {
                    switch page {
                    case .personal: PersonalView()
                    case .token: TokenView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(pageTitle)
            .toolbar { readerToolbar }
        }
        .tint(brandTint)
        .sheet(isPresented: $model.showPreview) { PreviewSheet() }
        .task { await model.startMonitoring() }
        #if !APPSTORE
        .task { if prefs.autoUpdate && !model.isDemoUI { await model.checkUpdates(manual: false) } }
        #endif
    }

    /// Own sidebar rows instead of a List: the system draws a selected List row in the user's accent colour
    /// (blue), and the app's accent is the red of the flag.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarRow(title: loc.t(.tabPersonal), icon: "person.text.rectangle", selected: page == .personal) { go(.personal) }
            SidebarRow(title: loc.t(.tabToken), icon: "key.viewfinder", selected: page == .token) { go(.token) }
            Spacer().frame(height: 14)
            SidebarRow(title: loc.t(.tabSettings), icon: "gearshape", selected: page == .settings) { go(.settings) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top, spacing: 0) { brandHeader }
    }

    private func go(_ p: Page) { shotPage = nil; pageRaw = p.rawValue }

    /// Logo and name at the top of the sidebar. The status (the reader's face) lives in the middle of the window.
    private var brandHeader: some View {
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

    /// Refresh (look for the reader again) is one button in the toolbar on every page; with several readers
    /// there is also a menu to choose which one to use.
    @ToolbarContentBuilder private var readerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.readers.count > 1 {
                Picker(loc.t(.reader), selection: $model.selectedReader) {
                    ForEach(model.readers, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu).help(loc.t(.reader))
            }
            Button { model.refresh() } label: { Label(loc.t(.refresh), systemImage: "arrow.clockwise") }
                .help(model.readers.first.map { "\(loc.t(.refresh)) — \($0)" } ?? loc.t(.refresh))
        }
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
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Personal data

struct PersonalView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Prefs
    @State private var showReaderHelp = false

    var body: some View {
        ZStack {
            if let p = model.personal {
                ScrollView {
                    summary(p)
                    .padding(20)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                emptyState.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.personal != nil)
        .toolbar { actions }
        .sheet(isPresented: $showReaderHelp) { ReaderHelpSheet() }
    }

    /// Nothing read yet: the reader's face says what is going on, the text says what to do next.
    /// (The status itself is in the sidebar, so it is not repeated here.)
    private var emptyState: some View {
        let mood = model.readerMood
        let title: Loc.L, hint: Loc.L?
        switch mood {
        case .busy: title = .statusReading; hint = nil
        case .noReader: title = .emptyNoReaderT; hint = .emptyNoReaderH
        case .waiting: title = .emptyNoCardT; hint = .emptyNoCardH
        case .ready, .error: title = model.cardPresent ? .emptyReadyT : .emptyNoCardT
                             hint = model.cardPresent ? .emptyReadyH : .emptyNoCardH
        }
        return VStack(spacing: 14) {
            MascotArt(character: .reader, mood: mood, size: 170)
            Text(loc.t(title)).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                .contentTransition(.opacity)
            if mood == .noReader {
                // a thin strip: which reader to get (opens the reader page inside the app)
                Button { showReaderHelp = true } label: {
                    Label(loc.t(.readerHelpTitle), systemImage: "questionmark.circle").font(.subheadline.weight(.medium))
                }
                .glassButton().controlSize(.small)
            }
            if let hint {
                Text(loc.t(hint)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    .contentTransition(.opacity)
            }
            if model.cardPresent && !model.busy {
                Button { Task { await model.readCard() } } label: {
                    Label(loc.t(.readCard), systemImage: "person.text.rectangle").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 6)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            sigPill
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: mood)
        .animation(.easeInOut(duration: 0.25), value: model.cardPresent)
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
                        .symbolReplace()
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
            // while nothing is read, the empty state has the one Read button
            if model.personal != nil {
                Button { Task { await model.readCard() } } label: {
                    Label(loc.t(.readCard), systemImage: "person.text.rectangle")
                }
                .labelStyle(.titleAndIcon).buttonStyle(.borderedProminent)
                .disabled(!model.cardPresent || model.busy).help(loc.t(.readCard))
            }
        }
    }

    /// Everything on one card, sized to fit the window without scrolling: photo on the left,
    /// name and all fields on the right.
    private func summary(_ p: PersonalData) -> some View {
        summaryCard(p)
    }

    private func summaryCard(_ p: PersonalData) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 20) {
                portrait(p)
                VStack(alignment: .leading, spacing: 12) {
                    // document type, then the name, then validity and the signature result, one per line on the left
                    VStack(alignment: .leading, spacing: 6) {
                        Text(docTypeName(p.cardType)).foregroundStyle(.secondary)
                        Text("\(p.fixed.givenName) \(p.fixed.surname)")
                            .font(.system(size: 22, weight: .bold))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let d = p.expiryDate { ExpiryPill(date: d) }
                        sigPill
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: sigKey)
                    Divider()
                    FieldGrid(rows: p.rows())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Changes whenever the signature result changes (the status itself is not Equatable).
    private var sigKey: Int {
        switch model.signatureStatus {
        case nil: return 0
        case .ok: return 1
        case .chainNotTrusted: return 2
        case .invalid: return 3
        case .unavailable: return 4
        }
    }

    @ViewBuilder private var sigPill: some View {
        switch model.signatureStatus {
        case .ok: Pill(text: loc.t(.sigOk), color: .green, icon: "checkmark.seal.fill").transition(.pop)
        case .chainNotTrusted: Pill(text: loc.t(.sigChain), color: .orange, icon: "exclamationmark.triangle.fill").transition(.pop)
        case .invalid: Pill(text: loc.t(.sigBad), color: .red, icon: "xmark.seal.fill").transition(.pop)
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
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: hidden)
            }
            Spacer(minLength: 4)
            CopyButton(value: row.value).opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
        .padding(.horizontal, -6).padding(.vertical, -4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Token

struct TokenView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                driverWarning   // above everything, so it is seen before the mascot
                firefoxWarning
                if model.tokenRows.isEmpty {
                    MascotArt(character: .key, mood: model.readerMood, size: 170)
                    Text(loc.t(.hintToken)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    ActionButton(title: loc.t(.readToken), icon: "key", prominent: true) { Task { await model.readToken() } }
                        .disabled(!model.cardPresent || model.busy)
                } else {
                    ForEach(model.tokenRows) { certificate($0) }
                }
                VStack(spacing: 10) {
                    ActionButton(title: loc.t(.changePin), icon: "lock.rotation") { Task { await model.changePin() } }
                    ActionButton(title: loc.t(.unblockPin), icon: "lock.open") { Task { await model.unblockPin() } }
                    ActionButton(title: loc.t(.signFile), icon: "signature") { Task { await model.signFile() } }
                }
                .disabled(!model.cardPresent || model.busy)
                // opens the sign-in page in the default browser; the system offers the card certificate there
                VStack(spacing: 6) {
                    ActionButton(title: loc.t(.loginEuprava), icon: "key.fill") {
                        NSWorkspace.shared.open(URL(string: "https://euprava.gov.rs/prijava")!)
                    }
                    Text(loc.t(.loginHint)).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button(loc.t(.loginCheckRun)) { Task { await model.runLoginCheck() } }
                        .buttonStyle(.link).font(.caption).disabled(model.busy)
                }
                loginReportCard
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.25), value: model.tokenRows.isEmpty)
        .task { await model.checkFirefox() }
        .task(id: model.cardPresent) {
            model.loginReport = nil        // what the check found is about the card that was in the reader then
            // the system needs a few seconds to attach the driver after the card is inserted
            guard model.cardPresent else { return }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { await model.checkDriverNow() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // while nothing is read, the empty state has the one Read button
                if !model.tokenRows.isEmpty {
                    Button { Task { await model.readToken() } } label: { Label(loc.t(.readToken), systemImage: "key") }
                        .labelStyle(.titleAndIcon).buttonStyle(.borderedProminent)
                        .disabled(!model.cardPresent || model.busy).help(loc.t(.readToken))
                }
            }
        }
    }

    /// Only when something is wrong (the card driver is not attached); otherwise nothing is shown.
    @ViewBuilder private var driverWarning: some View {
        if model.driverState == .missing {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(loc.t(.loginCheckMissing)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(loc.t(.loginCheckBtn)) { Task { await model.checkDriverNow() } }
                    .glassButton().controlSize(.small).disabled(!model.cardPresent || model.busy)
            }
            .padding(12).glassSurface(cornerRadius: 16)
        }
    }

    /// The result of "Check browser sign-in": a mark and a line for each thing that was looked at, then what to do next (and the button for it).
    @ViewBuilder private var loginReportCard: some View {
        if let report = model.loginReport {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(loc.t(.loginCheckTitle)).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Button { model.loginReport = nil } label: { Image(systemName: "xmark").font(.caption.weight(.semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                ForEach(report.lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: line.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(line.ok ? Color.green : Color.orange)
                        Text(loc.t(line.key)).font(.caption)
                        Spacer(minLength: 0)
                    }
                }
                Text(loc.t(report.step)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                if report.canRepair {
                    Button(loc.t(.repairBtn)) { Task { await model.repairLogin() } }
                        .glassButton(prominent: true).controlSize(.small).disabled(model.busy)
                }
                if report.canFixFirefox {
                    Button(loc.t(.firefoxFix)) { Task { await model.fixFirefox(); await model.runLoginCheck() } }
                        .glassButton(prominent: true).controlSize(.small).disabled(model.busy)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassSurface(cornerRadius: 16)
        }
    }

    /// Only when a Firefox profile is set not to use the keychain certificates: the card certificate would not show up in it.
    @ViewBuilder private var firefoxWarning: some View {
        if model.firefoxOff > 0 {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(loc.t(.firefoxOff)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                VStack(spacing: 6) {
                    Button(loc.t(.firefoxFix)) { Task { await model.fixFirefox() } }
                        .glassButton(prominent: true).controlSize(.small).disabled(model.busy)
                    Button(loc.t(.firefoxLater)) { model.dismissFirefox() }
                        .glassButton().controlSize(.small)
                }
            }
            .padding(12).glassSurface(cornerRadius: 16)
        }
    }

    /// The card holds two certificates: one to sign in, one to sign documents.
    private func purpose(_ row: TokenCertRow) -> (title: String, icon: String)? {
        let l = row.label.lowercased()
        if l.hasSuffix("auth") { return (loc.t(.certAuth), "person.badge.key.fill") }
        if l.hasSuffix("sign") { return (loc.t(.certSign), "signature") }
        return nil
    }

    private func certificate(_ row: TokenCertRow) -> some View {
        let p = purpose(row)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: p?.icon ?? "checkmark.seal").font(.title2).foregroundStyle(brandTint)
                        .frame(width: 30).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p?.title ?? row.summary?.subject ?? row.label).font(.headline)
                        if let s = row.summary {
                            Text([s.subject, s.issuer].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { model.exportCertificate(row) } label: { Image(systemName: "square.and.arrow.down").padding(2) }
                        .glassButton().help(loc.t(.exportCert))
                }
                if let s = row.summary {
                    HStack(spacing: 8) {
                        Pill(text: s.chainTrusted ? loc.t(.chainOk) : loc.t(.sigChain),
                             color: s.chainTrusted ? .green : .orange,
                             icon: s.chainTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        if let b = s.notAfter { ExpiryPill(date: b) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: AppModel

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
                #if !APPSTORE
                Toggle(loc.t(.setAutoUpdate), isOn: $prefs.autoUpdate)
                #endif
            }
            Section {
                Toggle(loc.t(.demoData), isOn: Binding(
                    get: { model.demoActive },
                    set: { $0 ? model.showDemoData() : model.hideDemoData() }))
            } footer: { Text(loc.t(.demoHint)) }
            Section(loc.t(.tabAbout)) { AboutView() }
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
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text(loc.t(.appTitle)).font(.title2.weight(.bold))
            Text("\(loc.t(.version)) \(Updater.currentVersion)").foregroundStyle(.secondary)
            Text(loc.t(.aboutText)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .font(.callout).frame(maxWidth: 400).padding(.top, 2)
            #if !APPSTORE
            Button { Task { await model.checkUpdates(manual: true) } } label: {
                Label(loc.t(.checkUpdates), systemImage: "arrow.triangle.2.circlepath")
            }
            .padding(.top, 6)
            if let s = model.updateStatus {
                Text(s).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            }
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
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
