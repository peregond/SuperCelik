import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A message shown in the banner under the header. `isInfo` = neutral note, otherwise an error.
struct Problem {
    var titleKey: Loc.L?
    var hintKey: Loc.L?
    var raw = ""
    var tech = ""
    var isInfo = false
}

struct TokenCertRow: Identifiable {
    let id = UUID()
    let label: String
    let summary: TokenCodec.CertSummary?
    let der: Data
}

/// One line of the browser sign-in check: whether it is in order, and what it says.
struct LoginCheckLine: Identifiable {
    let id = UUID()
    let ok: Bool
    let key: Loc.L
}

/// The result of "Check browser sign-in" on the Token tab: what was looked at, and the one thing to do next.
struct LoginReport {
    var lines: [LoginCheckLine]
    var step: Loc.L
    var canRepair = false         // registering the driver again can help (not in the sandboxed Mac App Store build)
    var canFixFirefox = false     // a Firefox profile is set not to use the keychain certificates
}

extension LoginReport {
    /// The lines and the one next step for what the check found; the first thing that is wrong decides the step.
    init(card: Bool, haveReader: Bool, registered: Bool?, attached: Bool, firefoxProfiles: Int, firefoxOff: Int, canRepair: Bool) {
        var lines: [LoginCheckLine] = [.init(ok: card, key: card ? .cardPresent : (haveReader ? .noCard : .noReader))]
        // one line for the driver: not registered / the card is not attached to it yet / in order
        if registered == false { lines.append(.init(ok: false, key: .chkExtNo)) }
        else if card { lines.append(.init(ok: attached, key: attached ? .chkAttachedOk : .chkAttachedNo)) }
        else if registered == true { lines.append(.init(ok: true, key: .chkExtOk)) }
        if firefoxProfiles > 0 { lines.append(.init(ok: firefoxOff == 0, key: firefoxOff == 0 ? .chkFfOk : .chkFfOff)) }

        self.init(lines: lines, step: .loginCheckOk)
        if registered == false {
            step = .stepRepair; self.canRepair = canRepair            // registering needs no card, so it comes first
        } else if !card {
            step = .loginCheckNoCard
        } else if !attached {
            step = .loginCheckMissing; self.canRepair = canRepair
        } else if firefoxOff > 0 {
            step = .stepFirefox; canFixFirefox = true
        }
    }
}

/// Last user-input time, kept outside the main actor so the NSEvent monitor can write it.
final class ActivityBox { var last = Date() }

@MainActor
final class AppModel: ObservableObject {
    @Published var readers: [String] = []
    @Published var selectedReader = ""
    @Published var atrHex: String?
    @Published var cardPresent = false { didSet { if cardPresent != oldValue { loginReport = nil } } }      // what "Check browser sign-in" found was about the card that was in the reader
    @Published var personal: PersonalData?
    @Published var token: TokenInfo?
    @Published var vehicle: VehicleData?
    @Published var diagUnlocked = false      // hidden: 5 taps on the version in Settings
    @Published var diagLog: String?
    @Published var tokenRows: [TokenCertRow] = []
    @Published var revealAll = false          // one global eye: show / hide all sensitive fields
    @Published var busy = false
    @Published var problem: Problem?
    @Published var showPreview = false

    /// Whether the system has attached our card driver to the inserted card (what browser sign-in needs).
    enum DriverState { case unknown, ok, missing }
    @Published var driverState: DriverState = .unknown

    /// Firefox profiles that are set not to use the keychain certificates (the card certificate would not show up in them), see FirefoxSetup.swift.
    @Published var firefoxOff = 0

    /// Shown under the sign-in button after "Check browser sign-in", until it is closed or the card changes.
    @Published var loginReport: LoginReport? { didSet { if loginReport != nil { loginReportSerial += 1 } } }
    @Published private(set) var loginReportSerial = 0        // counts the results shown: the Token tab scrolls to a new one

    @Published var update: UpdateInfo?
    @Published var updating = false
    @Published var updateStatus: String?

    enum SigStatus { case ok, chainNotTrusted(String), invalid(String), unavailable }
    @Published var signatureStatus: SigStatus?

    private var driverCheckGeneration = 0     // bumped on every card insertion / removal
    private(set) var service: CardService
    let isDemoUI: Bool
    private let prefs = Prefs.shared
    private let activity = ActivityBox()

    init() {
        let args = CommandLine.arguments
        isDemoUI = args.contains("--shot") || args.contains("--page") || ProcessInfo.processInfo.environment["SERBIAID_DEMO"] == "1"
        service = isDemoUI ? MockCardService() : PCSCService()
        if args.contains("--shot") || args.contains("--page") {
            Prefs.shared.theme = (args.contains("--dark") || args.contains("--night")) ? "dark" : "light"
            loadDemo(problem: args.contains("--problem"))
            if args.contains("--preview") { showPreview = true }   // print preview sheet, for the PDF screenshot
            if let i = args.firstIndex(of: "--state"), i + 1 < args.count { applyShotState(args[i + 1]) }
            if let i = args.firstIndex(of: "--check") { loginReport = AppModel.demoLoginReport(i + 1 < args.count && !args[i + 1].hasPrefix("--") ? args[i + 1] : "ok") }
        } else {
            initialRefresh = Task { await refreshAsync() }
            BrowserLogin.prepare()
        }
        let box = activity
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .keyDown, .scrollWheel]) { e in
            box.last = Date(); return e
        }
    }

    // MARK: - Readers + automatic card detection

    /// What the reader mascot shows.
    var readerMood: ReaderMood {
        if busy { return .busy }
        if readers.isEmpty { return .noReader }
        if let p = problem, !p.isInfo { return .error }
        return cardPresent ? .ready : .waiting
    }

    /// Fictional data shown from Settings (App Review has no Serbian eID). While it is on, polling is paused.
    @Published private(set) var demoActive = false
    func showDemoData() {
        demoActive = true
        loadDemo(problem: false)
    }

    /// Switch the demo data off again and go back to the real reader.
    func hideDemoData() {
        guard demoActive else { return }
        refresh()
    }

    private var initialRefresh: Task<Void, Never>?
    func refresh() { Task { await refreshAsync() } }

    /// PC/SC calls go through the system smart-card daemon and can block for a long time when it is stuck,
    /// so they never run on the main thread (a stuck daemon froze the whole window before).
    private func refreshAsync() async {
        if demoActive { demoActive = false; clearData() }
        let svc = service, current = selectedReader
        do {
            let (list, atr) = try await perform { () -> ([String], Data??) in
                let list = try svc.listReaders()
                let reader = list.contains(current) ? current : (list.first ?? "")
                return (list, reader.isEmpty ? nil : .some(try svc.atr(reader: reader)))
            }
            readers = list
            if !list.contains(selectedReader) { selectedReader = list.first ?? "" }
            guard !selectedReader.isEmpty else {
                cardPresent = false; atrHex = nil
                if problem?.isInfo == false { problem = nil }
                return
            }
            applyAtr(atr ?? nil)
            if cardPresent, problem?.isInfo == false { problem = nil }
        } catch { showProblem(error) }
    }

    private func applyAtr(_ atr: Data?) {
        if let atr {
            cardPresent = true
            atrHex = atr.map { String(format: "%02X", $0) }.joined(separator: " ")
        } else { cardPresent = false; atrHex = nil }
    }

    /// Runs forever from the root view: card insert / remove, and idle auto-hide.
    func startMonitoring() async {
        guard !isDemoUI else { return }
        await initialRefresh?.value      // so a card already in the reader at launch is seen before the checks below
        // A card that was already in the reader at launch never produces an "inserted" change.
        if cardPresent { checkDriver() }
        if prefs.autoRead, cardPresent, personal == nil { await readCard() }
        while !Task.isCancelled {
            await poll()
            checkIdle()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private func poll() async {
        guard !busy, !demoActive else { return }
        let svc = service, current = selectedReader
        do {
            // off the main thread: see refreshAsync()
            let (list, atr) = try await perform { () -> ([String], Data?) in
                let list = try svc.listReaders()
                let reader = list.contains(current) ? current : (list.first ?? "")
                return (list, reader.isEmpty ? nil : try svc.atr(reader: reader))
            }
            guard !busy, !demoActive else { return }
            if list != readers {
                readers = list
                if !list.contains(selectedReader) { selectedReader = list.first ?? "" }
            }
            var present = false
            if !selectedReader.isEmpty, let atr {
                present = true
                atrHex = atr.map { String(format: "%02X", $0) }.joined(separator: " ")
            } else { atrHex = nil }
            guard present != cardPresent else { return }
            cardPresent = present
            if present {
                if problem?.isInfo == false { problem = nil }
                checkDriver()
                if prefs.autoRead { Task { await readCard() } }
            } else {
                driverCheckGeneration += 1     // cancels a pending driver check
                driverState = .unknown
                clearData()          // privacy: drop data when the card is removed
            }
        } catch { /* reader unplugged mid-poll: a manual refresh reports it */ }
    }

    private func checkIdle() {
        guard !demoActive else { return }
        let m = prefs.autoHideMinutes
        guard m > 0, personal != nil || token != nil || vehicle != nil else { return }
        if Date().timeIntervalSince(activity.last) >= Double(m) * 60 {
            clearData()
            problem = Problem(titleKey: .autoHidden, isInfo: true)
        }
    }

    private func clearData() {
        personal = nil; token = nil; tokenRows = []; signatureStatus = nil; revealAll = false
        vehicle = nil
    }

    // MARK: - Operations (card I/O runs off the main thread)

    private func perform<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }

    private func run(_ work: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await work() } catch { showProblem(error) }
    }

    func readCard() async {
        await run {
            let svc = service, reader = selectedReader
            // one button for every card: an ID card, a foreigner card, a residence permit or a vehicle registration card
            if try await perform({ try svc.hasEidApplet(reader: reader) }) {
                let p = try await perform { try svc.readPersonalData(reader: reader) }
                personal = p; vehicle = nil; signatureStatus = nil; revealAll = false; problem = nil
            } else {
                let v = try await perform { try svc.readVehicle(reader: reader) }
                vehicle = v; personal = nil; signatureStatus = nil; revealAll = false
                problem = Problem(raw: Loc.shared.x("vehNote"), isInfo: true)
            }
        }
    }

    func verifySignatures() async {
        await run {
            let svc = service, reader = selectedReader
            let status: SigStatus = await Task.detached(priority: .userInitiated) { () -> SigStatus in
                do {
                    for s in [EidSignature.fixed, .variable] { _ = try svc.verify(reader: reader, signature: s) }
                    return .ok
                } catch CardError.chainNotTrusted(let m) { return .chainNotTrusted(m) }
                catch CardError.signature(let m) { return .invalid(m) }
                catch CardError.notImplemented { return .unavailable }
                catch CardError.unsupportedForCard { return .unavailable }
                catch { return .invalid(error.localizedDescription) }
            }.value
            signatureStatus = status; problem = nil
        }
    }

    func runDiagnostics() async {
        await run {
            let svc = service, reader = selectedReader
            diagLog = try await perform { try svc.diagnose(reader: reader) }
        }
    }

    func readToken() async {
        await run {
            let svc = service, reader = selectedReader
            let t = try await perform { try svc.readToken(reader: reader) }
            token = t
            tokenRows = t.certificates.map {
                TokenCertRow(label: $0.label, summary: TokenCodec.summarize(der: $0.der), der: $0.der)
            }
            problem = nil
        }
    }

    // MARK: - Browser-login driver self-check

    /// Runs once per card insertion: if macOS did not attach our CryptoTokenKit driver to the card,
    /// repair it in the background and tell the user the one thing they must do (re-insert the card).
    private func checkDriver() {
        guard !isDemoUI else { return }
        let reader = selectedReader
        driverCheckGeneration += 1
        let generation = driverCheckGeneration
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            // Only the latest insertion may act: a card pulled and re-inserted during the delay
            // invalidates this check (otherwise it would restart a driver that is still starting up).
            guard let self, self.driverCheckGeneration == generation else { return }
            let attached = await Task.detached { BrowserLogin.driverAttached() }.value
            guard self.driverCheckGeneration == generation, self.cardPresent, self.selectedReader == reader else { return }
            if attached {
                self.driverState = .ok
                if self.problem?.titleKey == .driverStuck { self.problem = nil }
                return
            }
            self.driverState = .missing
            await Task.detached { BrowserLogin.repairDriver() }.value
            if self.driverCheckGeneration == generation, self.cardPresent, self.problem == nil { self.problem = Problem(titleKey: .driverStuck, isInfo: true) }
        }
    }

    /// The "Check" button on the Token tab.
    func checkDriverNow() async {
        if isDemoUI { driverState = .ok; return }      // demo / screenshots: no real driver to check
        guard cardPresent else { driverState = .unknown; return }
        let attached = await Task.detached { BrowserLogin.driverAttached() }.value
        driverState = cardPresent ? (attached ? .ok : .missing) : .unknown
    }

    /// "Check browser sign-in": what the app sees (reader, card), what macOS has (the driver extension, the card attached to it) and what Firefox does,
    /// then the one thing to do next. Nothing is changed here; the buttons in the result do that.
    func runLoginCheck() async {
        if isDemoUI { loginReport = AppModel.demoLoginReport("ok"); return }        // demo / screenshots: no real driver to ask
        let card = cardPresent, haveReader = !readers.isEmpty
        let found = await Task.detached { () -> (registered: Bool?, attached: Bool, firefoxProfiles: Int, firefoxOff: Int) in
            let firefox = FirefoxSetup.check()
            return (BrowserLogin.extensionRegistered(), BrowserLogin.driverAttached(), firefox.profiles, firefox.disabled.count)
        }.value
        loginReport = LoginReport(card: card, haveReader: haveReader, registered: found.registered, attached: found.attached,
                                  firefoxProfiles: found.firefoxProfiles, firefoxOff: found.firefoxOff, canRepair: BrowserLogin.canRepair)
    }

    /// A made-up result for screenshots (`--check [ok|reinsert|firefox]`): all in order, the card not attached to the driver yet, or Firefox set not to use the keychain.
    static func demoLoginReport(_ variant: String) -> LoginReport {
        LoginReport(card: true, haveReader: true, registered: true, attached: variant != "reinsert",
                    firefoxProfiles: 1, firefoxOff: variant == "firefox" ? 1 : 0, canRepair: true)
    }

    /// The "Repair" button of the check: registers the driver again and stops a stale instance; the card has to be put in again afterwards.
    func repairLogin() async {
        guard !isDemoUI else { return }
        await Task.detached { BrowserLogin.repairDriver() }.value
        loginReport = nil
        problem = Problem(titleKey: .driverStuck, isInfo: true)
    }

    // MARK: - Firefox (takes the card certificate from the keychain too, when its preference for that is on)

    private static let firefoxDeclinedKey = "firefoxDeclined"      // the user answered "Not now": do not show the hint again

    func checkFirefox() async {
        guard !isDemoUI, !UserDefaults.standard.bool(forKey: Self.firefoxDeclinedKey) else { return }
        firefoxOff = await Task.detached { FirefoxSetup.check().disabled.count }.value
    }

    /// The "Turn on" button: switches the preference on in the profiles where it is off.
    func fixFirefox() async {
        let (fixed, wanted) = await Task.detached { () -> (Int, Int) in
            let status = FirefoxSetup.check()
            return (FirefoxSetup.enable(status), status.disabled.count)
        }.value
        let allDone = fixed == wanted          // "done" only when every profile was changed, otherwise the warning comes back with an error
        problem = Problem(titleKey: allDone ? .firefoxDone : .firefoxFail, isInfo: allDone)
        if fixed > 0 { UserDefaults.standard.set(false, forKey: Self.firefoxDeclinedKey) }
        firefoxOff = 0
        await checkFirefox()
    }

    /// The "Not now" button (some people switch the preference off on purpose).
    func dismissFirefox() {
        UserDefaults.standard.set(true, forKey: Self.firefoxDeclinedKey)
        firefoxOff = 0
    }

    // MARK: - Token PIN / PUK / signing (each wrong PIN/PUK burns a card try: one attempt, never retried)

    private func askSecrets(title: String, message: String, labels: [String]) -> [String]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: Loc.shared.t(.ok))
        alert.addButton(withTitle: Loc.shared.t(.cancel))
        // Each field gets a caption above it and an explicit width: inside NSAlert's accessory view an
        // NSSecureTextField with no width constraint collapses to a tiny pill.
        var fields: [NSSecureTextField] = []
        var rows: [NSView] = []
        for label in labels {
            let caption = NSTextField(labelWithString: label)
            caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            caption.textColor = .secondaryLabelColor
            let f = NSSecureTextField()
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 280).isActive = true
            fields.append(f)
            let row = NSStackView(views: [caption, f])
            row.orientation = .vertical; row.alignment = .leading; row.spacing = 3
            rows.append(row)
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.setFrameSize(stack.fittingSize)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = fields.first
        return alert.runModal() == .alertFirstButtonReturn ? fields.map { $0.stringValue } : nil
    }

    private static func validPin(_ p: String) -> Bool {
        (4...8).contains(p.count) && p.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    private func pinProblem(_ error: Error) {
        let l = Loc.shared
        if case CardError.pinWrong(let n) = error { problem = Problem(raw: l.t(.pinWrongMsg) + "\(n)", isInfo: true) }
        else if case CardError.pinBlocked = error { problem = Problem(titleKey: .pinBlockedMsg, isInfo: true) }
        else { showProblem(error) }
    }

    private func pinOperation(old: Loc.L, unblock: Bool) async {
        let l = Loc.shared
        let title = l.t(unblock ? .unblockPin : .changePin)
        // One question per dialog, so it is always clear which PIN is being asked for.
        guard let first = askSecrets(title: title, message: l.t(unblock ? .pinStepPuk : .pinStepOld) + "\n\n" + l.t(.pinWarn),
                                     labels: [l.t(old)]) else { return }
        guard let new1 = askSecrets(title: title, message: l.t(.pinStepNew), labels: [l.t(.newPin)]) else { return }
        guard let new2 = askSecrets(title: title, message: l.t(.pinStepConfirm), labels: [l.t(.confirmPin)]) else { return }
        let v = [first[0], new1[0], new2[0]]
        guard v.allSatisfy(Self.validPin) else { problem = Problem(titleKey: .pinInvalid, isInfo: true); return }
        guard v[1] == v[2] else { problem = Problem(titleKey: .pinMismatch, isInfo: true); return }
        guard !busy else { return }
        busy = true; defer { busy = false }
        let svc = service, reader = selectedReader
        do {
            try await perform {
                if unblock { try svc.unblockTokenPin(reader: reader, puk: v[0], new: v[1]) }
                else { try svc.changeTokenPin(reader: reader, old: v[0], new: v[1]) }
            }
            problem = Problem(titleKey: unblock ? .pinUnblocked : .pinChanged, isInfo: true)
        } catch { pinProblem(error) }
    }

    func changePin() async { await pinOperation(old: .currentPin, unblock: false) }
    func unblockPin() async { await pinOperation(old: .pukLabel, unblock: true) }

    /// Detached CMS (.p7s) over a chosen file, signed with the token key.
    func signFile() async {
        let open = NSOpenPanel()
        open.canChooseDirectories = false; open.allowsMultipleSelection = false
        guard open.runModal() == .OK, let src = open.url else { return }
        guard let v = askSecrets(title: Loc.shared.t(.signFile), message: Loc.shared.t(.pinWarn), labels: [Loc.shared.t(.currentPin)]) else { return }
        guard Self.validPin(v[0]) else { problem = Problem(titleKey: .pinInvalid, isInfo: true); return }
        let save = NSSavePanel()
        save.nameFieldStringValue = src.lastPathComponent + ".p7s"
        guard save.runModal() == .OK, let dst = save.url else { return }
        guard !busy else { return }
        busy = true; defer { busy = false }
        let svc = service, reader = selectedReader, pin = v[0], noCert = Loc.shared.t(.signNeedCert)
        do {
            let p7s: Data = try await perform {
                let tok = try svc.readToken(reader: reader)
                guard let cert = tok.certificates.first else { throw CardError.signature(noCert) }
                let data = try Data(contentsOf: src)
                return try CMSBuilder.signDetached(data: data, certDer: cert.der) { di in
                    try svc.tokenSign(reader: reader, pin: pin, keyFile: EidCard.defaultSignKeyFile, digestInfo: di)
                }
            }
            try p7s.write(to: dst)
            problem = Problem(raw: "\(Loc.shared.t(.signedSaved)): \(dst.lastPathComponent)", isInfo: true)
        } catch { pinProblem(error) }
    }

    // MARK: - Errors

    func showProblem(_ error: Error) {
        DiagLog.error(error)
        var t: Loc.L = .errGenericT, h: Loc.L = .errGenericH
        if let ce = error as? CardError {
            switch ce {
            case .pcsc(let code, _):
                switch UInt32(bitPattern: code) {
                case 0x8010002E: t = .errNoReaderT; h = .errNoReaderH
                case 0x8010000C, 0x80100069, 0x80100066: t = .errNoCardT; h = .errNoCardH
                default: break
                }
            case .unsupportedForCard: t = .errUnsupportedT; h = .errUnsupportedH
            default: break
            }
        }
        problem = Problem(titleKey: t, hintKey: h, tech: error.localizedDescription)
    }

    // MARK: - Copy / export

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyAll() {
        guard let p = personal else { return }
        copy(p.rows().map { "\(Loc.shared.t($0.label)): \($0.value)" }.joined(separator: "\n"))
        problem = Problem(titleKey: .copied, isInfo: true)
    }

    func savePhoto() {
        guard let d = personal?.portrait else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = "photo.jpg"
        if panel.runModal() == .OK, let url = panel.url { try? d.write(to: url) }
    }

    func exportJSON() {
        guard let p = personal else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SuperCelik.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var obj: [String: String] = ["cardType": String(describing: p.cardType)]
        for r in p.rows() { obj[r.id] = r.value }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? data.write(to: url)
        }
    }

    func exportCertificate(_ row: TokenCertRow) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "certificate.cer"
        if panel.runModal() == .OK, let url = panel.url { try? row.der.write(to: url) }
    }

    // MARK: - Updates

    /// manual = triggered from the About page (reports "up to date" / "unavailable").
    func checkUpdates(manual: Bool) async {
        if Updater.currentVersion == "0.0.0" && !manual { return }    // dev build (swift run)
        let r = await Updater.check()
        if let info = r.info { update = info; updateStatus = nil; return }
        if manual { updateStatus = r.reachable ? Loc.shared.t(.upToDate) : Loc.shared.t(.updateUnavailable) }
    }

    func installUpdate() async {
        guard let u = update else { return }
        updating = true
        do { try await Updater.install(u) }
        catch { problem = Problem(raw: "\(Loc.shared.t(.updateFailed)): \(error.localizedDescription)") }
        updating = false
    }

    // MARK: - Demo (fictional data, used by `--shot` and SERBIAID_DEMO=1)

    /// `--shot ... --state noreader|nocard|ready|busy|error`: the empty states, for UI review.
    private func applyShotState(_ state: String) {
        clearData()
        problem = nil
        switch state {
        case "noreader": readers = []; selectedReader = ""; cardPresent = false
        case "nocard": cardPresent = false
        case "busy": busy = true
        case "error": showProblem(CardError.unsupportedForCard)
        default: break     // "ready": reader + card, nothing read yet
        }
    }

    private func loadDemo(problem withProblem: Bool) {
        readers = ["Demo Reader"]; selectedReader = "Demo Reader"; cardPresent = true
        var p = PersonalData()
        p.cardType = .rp2024
        p.document = DocumentData(docRegNo: "001234567", documentType: "RP", issuingDate: "01.01.2024",
                                  expiryDate: {
                                      let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy"
                                      return f.string(from: Date().addingTimeInterval(412 * 86400))
                                  }(),
                                  issuingAuthority: "MUP RS", documentSerialNumber: "RS1234567")
        p.fixed = FixedPersonalData(personalNumber: "0101990710000", surname: "PETROVIĆ", givenName: "MARKO", sex: "M",
                                    stateOfBirth: "Srbija", dateOfBirth: "01.01.1990", nationalityFull: "Srbija")
        p.variable = VariablePersonalData(community: "Stari Grad", place: "Beograd", street: "Knez Mihailova", houseNumber: "1")
        personal = p
        signatureStatus = .ok
        // `--vehicle` with the demo: a vehicle registration card instead of the ID card
        if CommandLine.arguments.contains("--vehicle") { personal = nil; vehicle = VehicleRows.demo(); signatureStatus = nil }
        token = TokenInfo(tokenLabel: "NetSeT's CardEdge Token", tokenSerial: "RP000000000", certificates: [])
        tokenRows = [TokenCertRow(label: "MARKO PETROVIC 000000000 Auth",
                                  summary: TokenCodec.CertSummary(subject: "MARKO PETROVIC", issuer: "MUP Stranci CA 4",
                                                                  notBefore: Date().addingTimeInterval(-420 * 86400),
                                                                  notAfter: Date().addingTimeInterval(75 * 86400),
                                                                  chainTrusted: true, chainError: nil),
                                  der: Data()),
                     // the card has two certificates: one to sign in, one to sign documents (like the iPhone demo)
                     TokenCertRow(label: "MARKO PETROVIC 000000000 Sign",
                                  summary: TokenCodec.CertSummary(subject: "MARKO PETROVIC", issuer: "MUP Stranci CA 4",
                                                                  notBefore: Date().addingTimeInterval(-420 * 86400),
                                                                  notAfter: Date().addingTimeInterval(1040 * 86400),
                                                                  chainTrusted: true, chainError: nil),
                                  der: Data())]
        if withProblem { showProblem(CardError.pcsc(Int32(bitPattern: 0x8010002E), "ListReaders")) }
    }
}
