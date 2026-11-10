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

/// Last user-input time, kept outside the main actor so the NSEvent monitor can write it.
final class ActivityBox { var last = Date() }

@MainActor
final class AppModel: ObservableObject {
    @Published var readers: [String] = []
    @Published var selectedReader = ""
    @Published var atrHex: String?
    @Published var cardPresent = false
    @Published var personal: PersonalData?
    @Published var token: TokenInfo?
    @Published var tokenRows: [TokenCertRow] = []
    @Published var revealAll = false          // one global eye: show / hide all sensitive fields
    @Published var busy = false
    @Published var problem: Problem?
    @Published var showPreview = false

    @Published var update: UpdateInfo?
    @Published var updating = false
    @Published var updateStatus: String?

    enum SigStatus { case ok, chainNotTrusted(String), invalid(String), unavailable }
    @Published var signatureStatus: SigStatus?

    private(set) var service: CardService
    let isDemoUI: Bool
    private let prefs = Prefs.shared
    private let activity = ActivityBox()

    init() {
        let args = CommandLine.arguments
        isDemoUI = args.contains("--shot") || ProcessInfo.processInfo.environment["SERBIAID_DEMO"] == "1"
        service = isDemoUI ? MockCardService() : PCSCService()
        if args.contains("--shot") {
            if args.contains("--dark") { Prefs.shared.theme = "dark" }
            loadDemo(problem: args.contains("--problem"))
        } else {
            refresh()
            BrowserLogin.prepare()
        }
        let box = activity
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .keyDown, .scrollWheel]) { e in
            box.last = Date(); return e
        }
    }

    // MARK: - Readers + automatic card detection

    func refresh() {
        do {
            let list = try service.listReaders()
            readers = list
            if !list.contains(selectedReader) { selectedReader = list.first ?? "" }
            guard !selectedReader.isEmpty else {
                cardPresent = false; atrHex = nil
                showProblem(CardError.pcsc(Int32(bitPattern: 0x8010002E), "ListReaders")); return
            }
            applyAtr(try service.atr(reader: selectedReader))
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
        // A card that was already in the reader at launch never produces an "inserted" change.
        if prefs.autoRead, cardPresent, personal == nil { await readCard() }
        while !Task.isCancelled {
            poll()
            checkIdle()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private func poll() {
        guard !busy else { return }
        do {
            let list = try service.listReaders()
            if list != readers {
                readers = list
                if !list.contains(selectedReader) { selectedReader = list.first ?? "" }
            }
            var present = false
            if !selectedReader.isEmpty, let atr = try service.atr(reader: selectedReader) {
                present = true
                atrHex = atr.map { String(format: "%02X", $0) }.joined(separator: " ")
            } else { atrHex = nil }
            guard present != cardPresent else { return }
            cardPresent = present
            if present {
                if problem?.isInfo == false { problem = nil }
                if prefs.autoRead { Task { await readCard() } }
            } else {
                clearData()          // privacy: drop data when the card is removed
            }
        } catch { /* reader unplugged mid-poll: a manual refresh reports it */ }
    }

    private func checkIdle() {
        let m = prefs.autoHideMinutes
        guard m > 0, personal != nil || token != nil else { return }
        if Date().timeIntervalSince(activity.last) >= Double(m) * 60 {
            clearData()
            problem = Problem(titleKey: .autoHidden, isInfo: true)
        }
    }

    private func clearData() {
        personal = nil; token = nil; tokenRows = []; signatureStatus = nil; revealAll = false
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
            let p = try await perform { try svc.readPersonalData(reader: reader) }
            personal = p; signatureStatus = nil; revealAll = false; problem = nil
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

    // MARK: - Token PIN / PUK / signing (each wrong PIN/PUK burns a card try: one attempt, never retried)

    private func askSecrets(title: String, labels: [String]) -> [String]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = Loc.shared.t(.pinWarn)
        alert.addButton(withTitle: Loc.shared.t(.ok))
        alert.addButton(withTitle: Loc.shared.t(.cancel))
        let fields = labels.map { label -> NSSecureTextField in
            let f = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22)); f.placeholderString = label; return f
        }
        let stack = NSStackView(views: fields)
        stack.orientation = .vertical; stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: CGFloat(fields.count) * 30)
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
        guard let v = askSecrets(title: l.t(unblock ? .unblockPin : .changePin),
                                 labels: [l.t(old), l.t(.newPin), l.t(.confirmPin)]) else { return }
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
        guard let v = askSecrets(title: Loc.shared.t(.signFile), labels: [Loc.shared.t(.currentPin)]) else { return }
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
        token = TokenInfo(tokenLabel: "NetSeT's CardEdge Token", tokenSerial: "RP000000000", certificates: [])
        tokenRows = [TokenCertRow(label: "MARKO PETROVIC 000000000 Auth",
                                  summary: TokenCodec.CertSummary(subject: "MARKO PETROVIC", issuer: "MUP Stranci CA 4",
                                                                  notBefore: Date().addingTimeInterval(-420 * 86400),
                                                                  notAfter: Date().addingTimeInterval(75 * 86400),
                                                                  chainTrusted: true, chainError: nil),
                                  der: Data())]
        if withProblem { showProblem(CardError.pcsc(Int32(bitPattern: 0x8010002E), "ListReaders")) }
    }
}
