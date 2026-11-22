import SwiftUI
import UIKit
import SafariServices
import UniformTypeIdentifiers

struct PhoneRootView: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: PhoneModel
    @ObservedObject private var quick = QuickActions.shared
    // screenshots only: `--token` / `--settings` open that tab at launch
    @State private var tab = CommandLine.arguments.contains("--token") ? 1 : (CommandLine.arguments.contains("--settings") ? 2 : 0)

    var body: some View {
        tabs
            .minimizingTabBar()
            .task { await model.watchReader() }
            .onChange(of: tab) { model.activeTab = $0 }
            .onChange(of: quick.pending) { _ in Task { await runQuickAction() } }
            .task { await runQuickAction() }       // app was started by the action
    }

    /// Home Screen quick action: switch to the right tab and do it.
    private func runQuickAction() async {
        guard let action = quick.pending else { return }
        quick.pending = nil
        switch action {
        case .readCard:
            tab = 0; model.activeTab = 0
            await model.scanCardAuto()
        case .printCard:
            tab = 0; model.activeTab = 0
            // print only what THIS call just read: never the data of a previous card
            if await model.scanCardAuto(), model.personal != nil { model.printPDF(includeJmbg: Prefs.shared.printJmbg) }
        case .loginEuprava:
            tab = 1; model.activeTab = 1
            model.loginRequested = true
        }
    }

    /// iPhone: tab bar (Liquid Glass). iPad: iOS 18+ turns the same tabs into a sidebar like the Mac app.
    @ViewBuilder private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $tab) {
                Tab(loc.t(.tabCardShort), systemImage: "person.text.rectangle", value: 0) { CardTab() }
                Tab(loc.t(.tabTokenShort), systemImage: "checkmark.seal", value: 1) { TokenTab() }
                Tab(loc.t(.tabSettings), systemImage: "gearshape", value: 2) { SettingsTab() }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $tab) {
                CardTab()
                    .tabItem { Label(loc.t(.tabCardShort), systemImage: "person.text.rectangle") }.tag(0)
                TokenTab()
                    .tabItem { Label(loc.t(.tabTokenShort), systemImage: "checkmark.seal") }.tag(1)
                SettingsTab()
                    .tabItem { Label(loc.t(.tabSettings), systemImage: "gearshape") }.tag(2)
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
    @EnvironmentObject var model: PhoneModel
    let problem: PhoneProblem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Label(loc.t(problem.title), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.orange)
                Text(loc.t(problem.hint)).font(.subheadline)
            }
            Spacer(minLength: 0)
            // the message can be dismissed; it comes back only with the next failed read
            Button { withAnimation(.easeOut(duration: 0.2)) { model.problem = nil } } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(.secondary).padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(loc.t(.close))
        }
        .padding(.vertical, 4)
    }
}

/// The character plus what the reader is doing right now: nothing plugged in, waiting for a card, ready to read.
/// It changes the moment a reader is plugged in or a card goes in (see PhoneModel.watchReader).
struct ReaderStatusBlock: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: PhoneModel
    let character: PhoneMascot.Character
    var size: CGFloat = 190
    var done = false
    /// Card tab, no reader: a thin "no reader?" strip between the title and the hint.
    var onHelp: (() -> Void)? = nil

    private var mood: PhoneMascot.Mood {
        if model.problem != nil && !done { return .error }
        if model.busy { return .busy }
        if done { return .done }
        switch model.readerState {
        case .none: return .noReader
        case .noCard: return .waiting
        case .cardReady: return .ready
        }
    }

    private var texts: (title: Loc.L, hint: Loc.L, color: Color) {
        switch model.readerState {
        case .none: return (.emptyNoReaderT, .iosNoReaderQ, .secondary)
        case .noCard: return (.emptyNoCardT, .iosNoCardH, .orange)
        case .cardReady: return (.emptyReadyT, .iosReadyH, .green)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            PhoneMascot(character: character, mood: mood, size: size)
            // demo data has no reader behind it: don't show "connect a reader" under a happy mascot
            if (model.problem == nil || done) && !(done && model.demoActive) {
                let t = texts
                Label(loc.t(t.title), systemImage: "circle.fill")
                    .labelStyle(StatusDotStyle(color: t.color))
                    .font(.headline)
                if let onHelp, model.readerState == .none { ReaderHelpCard(action: onHelp) }
                Text(loc.t(t.hint)).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.readerState)
    }
}

private struct StatusDotStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            configuration.title
        }
    }
}

/// The one main button: the app picks the wired reader if one is connected, otherwise NFC.
struct ScanButton: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: PhoneModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    let title: Loc.L
    var collapsed = false
    /// Token tab: scrolling down hides the button completely instead of shrinking it to a circle.
    var hideWhenCollapsed = false
    let action: () async -> Void

    /// Full width with a caption at the top of the screen; a round button in the bottom-right corner while scrolling down
    /// (like the tab bar shrinking into the bottom-left corner).
    var body: some View {
        HStack(spacing: 0) {
            if collapsed { Spacer(minLength: 0) }
            if collapsed && hideWhenCollapsed { EmptyView() }
            else if collapsed { roundButton } else { wideButton }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: collapsed)
    }

    private var wideButton: some View {
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
        .buttonBorderShape(.capsule)
        .tint(.blue)
        .controlSize(.large)
        .disabled(model.busy)
        .accessibilityLabel(loc.t(title))
    }

    /// Same size (48 pt) and the same baseline as the minimized tab bar button in the bottom-left corner:
    /// the bottom inset still reserves the full tab bar height, so the round button drops by that much.
    @ViewBuilder private var roundButton: some View {
        let icon = Group {
            if model.busy { ProgressView().tint(.white) } else { Image(systemName: model.autoIcon).font(.title3.weight(.semibold)) }
        }
        .foregroundStyle(.white)
        .frame(width: ScanButton.roundSize, height: ScanButton.roundSize)
        .contentShape(Circle())
        let button = Button { Task { await action() } } label: { icon }
            .buttonStyle(.plain)
            .disabled(model.busy)
            .accessibilityLabel(loc.t(title))
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // only the iPhone tab bar minimizes into the corner; the iPad sidebar / top tabs leave the inset as is
            // (a tall, narrow window: on iPhone Duo's squarer screen the tab bar is a side bar, nothing to line up with)
            let minimized = sizeClass == .compact && ScanButton.windowIsTall
            button
                .glassEffect(.regular.tint(.blue).interactive(), in: .circle)
                .offset(x: minimized ? 8 : 0, y: minimized ? ScanButton.roundDrop : 0)
        } else {
            button.background(Circle().fill(Color.blue))
        }
        #else
        button.background(Circle().fill(Color.blue))
        #endif
    }

    static var windowIsTall: Bool {
        let b = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.coordinateSpace.bounds
            ?? UIScreen.main.bounds
        return b.width > 0 && max(b.width, b.height) / min(b.width, b.height) > 1.7
    }

    static let roundSize: CGFloat = 48
    static let roundDrop: CGFloat = 56
}

/// Reports "scrolled down" for the scan button: collapses when scrolling down, comes back when scrolling up or at the top.
/// (iOS 18+; older systems keep the full button.)
struct ScrollCollapse: ViewModifier {
    @Binding var collapsed: Bool
    func body(content: Content) -> some View {
        // content that fits the screen stays put: no rubber-band bounce (the mascot and text used to jitter)
        let fixed = Group {
            if #available(iOS 16.4, *) { content.scrollBounceBehavior(.basedOnSize) } else { content }
        }
        if #available(iOS 18.0, *) {
            fixed.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { old, new in
                if new < 24 { collapsed = false }
                else if new > old + 3 { collapsed = true }
                else if new < old - 3 { collapsed = false }
            }
        } else {
            fixed
        }
    }
}

// MARK: - Card

struct CardTab: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: PhoneModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var share: ShareItem?
    @State private var pdf: ShareItem?
    @State private var photoOpen = false
    @State private var scanCollapsed = false
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let problem = model.problem {
                        ProblemBanner(problem: problem).padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                    }
                    if model.personal == nil {
                        ReaderStatusBlock(character: .reader, onHelp: { showHelp = true }).padding(.top, model.problem == nil ? 40 : 8)
                    }
                    if let p = model.personal {
                        if sizeClass == .regular { regularLayout(p) } else { compactLayout(p) }
                    }
                }
                .padding(16)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .modifier(ScrollCollapse(collapsed: $scanCollapsed))
            .background(GlassBackdrop())
            .navigationTitle(loc.t(.tabPersonal))
            .navigationBarTitleDisplayMode(.inline)
            .animation(.easeInOut(duration: 0.25), value: model.personal == nil)
            .safeAreaInset(edge: .bottom) {
                // after a read the button goes away; the "x" at the top left brings it back
                if model.personal == nil {
                    ScanButton(title: .readCardAuto, collapsed: scanCollapsed) { await model.scanCardAuto() }
                        .padding(.horizontal, 20).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
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
                        Button(role: .destructive) { model.clear() } label: { Image(systemName: "xmark").foregroundStyle(.red) }
                            .accessibilityLabel(loc.t(.close))
                    }
                }
            }
            .sheet(item: $share) { ShareSheet(url: $0.url) }
            .fullScreenCover(isPresented: $showHelp) {
                SafariView(url: URL(string: "https://celik.peregon.cc/reader/")!).ignoresSafeArea()
            }
            .sheet(item: $pdf) { PDFPreview(url: $0.url) }
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
        fieldsCard(p, columns: 1)
        actions
    }

    /// iPad: like the Mac window: name, signature and actions on the left, all fields on the right, one screen.
    @ViewBuilder private func regularLayout(_ p: PersonalData) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                header(p).padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
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
            Button { model.printPDF(includeJmbg: prefs.printJmbg) } label: {
                Label(loc.t(.printCard), systemImage: "printer").frame(maxWidth: .infinity).padding(.vertical, 6)
            }.glassButton(prominent: false)
            Button { model.copyAll() } label: {
                Label(loc.t(.copyAll), systemImage: "doc.on.doc").frame(maxWidth: .infinity).padding(.vertical, 6)
            }.glassButton(prominent: false)
            HStack(spacing: 10) {
                if model.personal?.portrait != nil {
                    Button { if let url = model.photoFile() { share = ShareItem(url: url) } } label: {
                        Label(loc.t(.savePhoto), systemImage: "photo").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.glassButton(prominent: false)
                }
                Button { if let url = model.jsonFile() { share = ShareItem(url: url) } } label: {
                    Label(loc.t(.exportJson), systemImage: "curlybraces").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity).padding(.vertical, 6)
                }.glassButton(prominent: false)
            }
        }
    }

    private func header(_ p: PersonalData) -> some View { headerContent(p) }

    private func headerContent(_ p: PersonalData) -> some View {
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
                    if let sig = model.signatureStatus { signatureRow(sig).font(.caption) }
                    Button { if let url = model.pdfFile(includeJmbg: prefs.printJmbg) { share = ShareItem(url: url) } } label: {
                        Label(loc.t(.sharePdf), systemImage: "square.and.arrow.up").font(.subheadline)
                    }
                    .glassButton(prominent: false).buttonBorderShape(.capsule).padding(.top, 4)
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
            Label(loc.t(.sigOk), systemImage: "signature").foregroundStyle(.green)
        case .chainNotTrusted(let m):
            VStack(alignment: .leading, spacing: 4) {
                Label(loc.t(.sigChain), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(m).font(.caption2).foregroundStyle(.secondary)
            }
        case .invalid(let m):
            VStack(alignment: .leading, spacing: 4) {
                Label(loc.t(.sigBad), systemImage: "xmark.seal.fill").foregroundStyle(.red)
                Text(m).font(.caption2).foregroundStyle(.secondary)
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
    @State private var scanCollapsed = false
    @State private var pinMode: PinMode?
    @State private var showLogin = false
    @State private var askLogin = false
    @State private var importing = false
    @State private var signing: PendingSign?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let problem = model.problem, model.token == nil {
                        ProblemBanner(problem: problem).padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                    }
                    ReaderStatusBlock(character: .key, size: model.token == nil ? 170 : 72, done: model.token != nil)
                    if model.token != nil {
                        ForEach(model.tokenRows) { certificate($0) }
                    }
                    GlassGroup(spacing: 10) {
                        action("lock.rotation", .changePin) { pinMode = .change }
                        action("lock.open", .unblockPin) { pinMode = .unblock }
                        action("signature", .signFile) { importing = true }
                    }
                    .disabled(model.busy || (model.readerState != .cardReady && !PhoneModel.screenshotMode))
                    // Sign in to eUprava: Safari takes the card certificate from the token extension inside this app.
                    Button { if model.driverAttached { showLogin = true } else { askLogin = true } } label: {
                        Label(loc.t(.loginEuprava), systemImage: "key.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.glassButton(prominent: false)
                }
                .padding(16)
                .frame(maxWidth: 520)   // on iPad the buttons stay a sensible width
                .frame(maxWidth: .infinity)
            }
            .modifier(ScrollCollapse(collapsed: $scanCollapsed))
            .background(GlassBackdrop())
            .navigationTitle(loc.t(.tabToken))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if model.token == nil {
                    ScanButton(title: .readToken, collapsed: scanCollapsed, hideWhenCollapsed: true) { await model.scanTokenAuto() }
                        .padding(.horizontal, 20).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.token == nil)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if model.token != nil {
                        Button(role: .destructive) { model.clear() } label: { Image(systemName: "xmark").foregroundStyle(.red) }
                            .accessibilityLabel(loc.t(.close))
                    }
                }
            }
            .sheet(item: $share) { ShareSheet(url: $0.url) }
            .onChange(of: model.loginRequested) { requested in
                guard requested else { return }
                model.loginRequested = false
                if model.driverAttached { showLogin = true } else { askLogin = true }
            }
            .onAppear {
                if model.loginRequested { model.loginRequested = false; if model.driverAttached { showLogin = true } else { askLogin = true } }
            }
            .sheet(item: $pinMode) { PinSheet(mode: $0) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                guard case .success(let url) = result else { return }
                // read off the main thread (a slow file provider must not freeze the UI), and not more than 100 MB
                Task {
                    // nil = unreadable, -1 size = too large
                    let picked = await Task.detached { () -> (PendingSign?, Bool) in
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        if size > 100_000_000 { return (nil, true) }
                        guard let data = try? Data(contentsOf: url) else { return (nil, false) }
                        return (PendingSign(name: url.lastPathComponent, data: data), false)
                    }.value
                    if let file = picked.0 { signing = file } else { model.pinAlert = loc.t(picked.1 ? .fileTooLarge : .fileUnreadable) }
                }
            }
            .sheet(item: $signing) { pending in
                SignSheet(file: pending) { url in
                    // the signing sheet closes first, then the share sheet offers to save the .p7s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { share = ShareItem(url: url) }
                }
            }
            .alert(loc.t(.loginEuprava), isPresented: $askLogin) {
                Button(loc.t(.loginEuprava)) { showLogin = true }
                Button(loc.t(.cancel), role: .cancel) {}
            } message: { Text(loc.t(.loginNoDriver)) }
            .fullScreenCover(isPresented: $showLogin) {
                SafariView(url: URL(string: "https://euprava.gov.rs/prijava")!).ignoresSafeArea()
            }
            .alert(model.pinAlert ?? "", isPresented: Binding(get: { model.pinAlert != nil && pinMode == nil },
                                                               set: { if !$0 { model.pinAlert = nil } })) {
                Button(loc.t(.ok)) { model.pinAlert = nil }
            }
        }
    }

    private func action(_ icon: String, _ title: Loc.L, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(loc.t(title), systemImage: icon).frame(maxWidth: .infinity).padding(.vertical, 6)
        }.glassButton(prominent: false)
    }

    private func purpose(_ row: PhoneCertRow) -> String? {
        let l = row.label.lowercased()
        if l.hasSuffix("auth") { return loc.t(.certAuth) }
        if l.hasSuffix("sign") { return loc.t(.certSign) }
        return nil
    }

    private func purposeIcon(_ row: PhoneCertRow) -> String {
        let l = row.label.lowercased()
        if l.hasSuffix("auth") { return "person.badge.key.fill" }
        if l.hasSuffix("sign") { return "signature" }
        return "checkmark.seal"
    }

    private func certificate(_ row: PhoneCertRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: purposeIcon(row)).font(.title2).foregroundStyle(.tint)
                    .frame(width: 30).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    // the card holds two certificates: one to sign in, one to sign documents
                    Text(purpose(row) ?? row.summary?.subject ?? row.label).font(.headline)
                    if let s = row.summary {
                        Text([s.subject, s.issuer].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    if let url = model.temporaryFile(row.der, name: "certificate.cer") { share = ShareItem(url: url) }
                } label: { Image(systemName: "square.and.arrow.up").padding(2) }
                    .glassButton(prominent: false).buttonBorderShape(.capsule)
                    .accessibilityLabel(loc.t(.exportCert))
            }
            if let s = row.summary {
                VStack(alignment: .leading, spacing: 4) {
                    if s.chainTrusted {
                        Label(loc.t(.chainOk), systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        Label(loc.t(.sigChain), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    if let b = s.notAfter {
                        let days = daysUntil(b)
                        if days < 0 { Label(loc.t(.expiredOn), systemImage: "xmark.circle.fill").foregroundStyle(.red) }
                        else { Label(String(format: loc.t(.expiresIn), days), systemImage: "clock.fill")
                            .foregroundStyle(days <= 90 ? Color.orange : Color.green) }
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

/// Quiet state of the Card tab: a thin strip under the "connect a reader" text that opens the page
/// about readers inside the app.
struct ReaderHelpCard: View {
    @EnvironmentObject var loc: Loc
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(loc.t(.readerHelpTitle), systemImage: "questionmark.circle")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 6)
        }
        .glassButton(prominent: false)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }
}

/// In-app Safari (SFSafariViewController): the same TLS client certificate flow as Safari, so the card certificate
/// offered by the token extension is used.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// MARK: - Token PIN / PUK

enum PinMode: Identifiable {
    case change, unblock
    var id: Int { self == .change ? 0 : 1 }
}

/// One form: current PIN (or PUK), new PIN twice. The warning about used-up tries is always visible.
struct PinSheet: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    let mode: PinMode
    @State private var secret = ""
    @State private var new = ""
    @State private var confirm = ""

    private var unblock: Bool { mode == .unblock }
    private var ready: Bool { PhoneModel.validPin(secret) && PhoneModel.validPin(new) && new == confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(loc.t(unblock ? .pukLabel : .currentPin), text: $secret)
                    SecureField(loc.t(.newPin), text: $new)
                    SecureField(loc.t(.confirmPin), text: $confirm)
                } footer: { Text(loc.t(.pinWarn)) }
                if let msg = model.pinAlert {
                    Section { Text(msg).foregroundStyle(.orange) }
                }
            }
            .keyboardType(.numberPad)
            .navigationTitle(loc.t(unblock ? .unblockPin : .changePin))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(loc.t(.cancel)) { model.pinAlert = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t(.ok)) {
                        Task {
                            if await model.pinOperation(secret: secret, new: new, confirm: confirm, unblock: unblock) { dismiss() }
                        }
                    }
                    .disabled(!ready || model.busy)
                }
            }
        }
        .onAppear { model.pinAlert = nil }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Sign a file

struct PendingSign: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
}

/// Asks for the token PIN and makes a detached CMS signature (.p7s) over the chosen file.
struct SignSheet: View {
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    let file: PendingSign
    let onSigned: (URL) -> Void
    @State private var pin = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("File", value: file.name)
                    SecureField(loc.t(.currentPin), text: $pin)
                } footer: { Text(loc.t(.pinWarn)) }
                if let msg = model.pinAlert {
                    Section { Text(msg).foregroundStyle(.orange) }
                }
            }
            .keyboardType(.numberPad)
            .navigationTitle(loc.t(.signFile))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(loc.t(.cancel)) { model.pinAlert = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t(.ok)) {
                        Task {
                            if let url = await model.signFile(data: file.data, name: file.name, pin: pin) { dismiss(); onSigned(url) }
                        }
                    }
                    .disabled(!PhoneModel.validPin(pin) || model.busy || model.readerState != .cardReady)
                }
            }
        }
        .onAppear { model.pinAlert = nil }
        .presentationDetents([.medium])
    }
}

// MARK: - Settings / about

struct SettingsTab: View {
    @EnvironmentObject var model: PhoneModel
    @EnvironmentObject var loc: Loc
    @EnvironmentObject var prefs: Prefs

    @State private var logsCopied = false

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
                .listRowBackground(Rectangle().fill(.regularMaterial))
                Section(loc.t(.setBehavior)) {
                    Toggle(loc.t(.setAutoRead), isOn: $prefs.autoRead)
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
                Section(loc.t(.setPrivacy)) {
                    Toggle(loc.t(.setMask), isOn: $prefs.maskSensitive)
                    Toggle(loc.t(.setPrintJmbg), isOn: $prefs.printJmbg)
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
                Section {
                    Toggle(loc.t(.demoData), isOn: Binding(
                        get: { model.demoActive },
                        set: { $0 ? model.loadDemo() : model.hideDemo() }))
                } footer: { Text(loc.t(.demoHint)) }
                .listRowBackground(Rectangle().fill(.regularMaterial))
                Section {
                    Button {
                        UIPasteboard.general.string = DiagLog.report(version: version, language: loc.language.rawValue, state: "")
                        logsCopied = true
                    } label: {
                        Label(loc.t(logsCopied ? .copyLogsDone : .copyLogs), systemImage: logsCopied ? "checkmark.circle" : "doc.on.doc")
                    }
                } footer: { Text(loc.t(.copyLogsHint)) }
                .listRowBackground(Rectangle().fill(.regularMaterial))
                Section(loc.t(.tabAbout)) {
                    Text(loc.t(.aboutTextIOS)).font(.subheadline)
                    LabeledContent(loc.t(.version), value: version)
                    Link(loc.t(.whatsNew), destination: loc.changelogURL)
                    Link(loc.t(.betaReport), destination: Loc.feedbackURL)
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackdrop())
            .navigationTitle(loc.t(.tabSettings))
        }
    }
}
