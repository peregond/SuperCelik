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
    @Published var revealed: Set<String> = []
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
        personal = nil; token = nil; tokenRows = []; signatureStatus = nil; revealed = []
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
            personal = p; signatureStatus = nil; revealed = []; problem = nil
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
