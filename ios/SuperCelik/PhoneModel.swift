import SwiftUI
import UIKit
import CryptoTokenKit

/// A message shown above the data: title + hint (both localized) + technical details.
struct PhoneProblem {
    var title: Loc.L
    var hint: Loc.L
    var tech = ""
}

struct PhoneCertRow: Identifiable {
    let id = UUID()
    let label: String
    let summary: TokenCodec.CertSummary?
    let der: Data
}

@MainActor
final class PhoneModel: ObservableObject {
    enum SigStatus { case ok, chainNotTrusted(String), invalid(String), unavailable }

    @Published var personal: PersonalData?
    @Published var signatureStatus: SigStatus?
    @Published var token: TokenInfo?
    @Published var tokenRows: [PhoneCertRow] = []
    @Published var revealAll = false
    @Published var busy = false
    @Published private(set) var demoActive = false     // fictional data on screen (Settings toggle)
    @Published var problem: PhoneProblem?
    /// Result of a PIN / PUK operation, shown in an alert.
    @Published var pinAlert: String?
    /// A quick action asked for the eUprava sign-in: the Token tab opens it.
    @Published var loginRequested = false
    /// Tab on screen (0 card, 1 token): automatic reading reads what that tab shows.
    var activeTab = 0
    /// Live state of the wired reader (see `watchReader`).
    @Published private(set) var readerState: ReaderState = .none

    enum ReadSource { case usb, nfc }

    /// NFC reading is parked for now: the code (NFCCardReader) stays, but the app only offers wired readers.
    static let nfcEnabled = false

    /// `--shots` launch argument (screenshot script only): PIN / PUK / signing buttons look enabled without a card.
    static let screenshotMode = CommandLine.arguments.contains("--shots")

    /// `--demo` launch argument: fictional data for screenshots (never touches a card).
    init() {
        if CommandLine.arguments.contains("--demo") { loadDemo() }
    }

    /// Fictional data shown without a card (App Review has no Serbian eID; also used for screenshots).
    func loadDemo() {
        var p = PersonalData()
        p.cardType = .rp2024
        p.document = DocumentData(docRegNo: "001234567", documentType: "RP", issuingDate: "01.01.2024",
                                  expiryDate: "01.01.2030", issuingAuthority: "MUP RS", documentSerialNumber: "RS1234567", documentName: "Dozvola za privremeni boravak i rad")
        p.fixed = FixedPersonalData(personalNumber: "0101990710000", surname: "PETROVIĆ", givenName: "MARKO", sex: "M",
                                    placeOfBirth: "Beograd", stateOfBirth: "Srbija", dateOfBirth: "01.01.1990", nationalityFull: "Srbija", purposeOfStay: "Rad")
        p.variable = VariablePersonalData(state: "Srbija", community: "Stari Grad", place: "Beograd", street: "Knez Mihailova", houseNumber: "1", addressDate: "01.01.2024")
        let size = CGSize(width: 240, height: 310)
        p.portrait = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { ctx in
            UIColor(red: 0.85, green: 0.89, blue: 0.94, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.56, green: 0.64, blue: 0.75, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 64, y: 64, width: 112, height: 112))
            ctx.cgContext.fillEllipse(in: CGRect(x: 30, y: 190, width: 180, height: 210))
        }
        personal = p
        signatureStatus = .ok
        // the Token tab gets fictional certificates too
        token = TokenInfo(tokenLabel: "NetSeT's CardEdge Token", tokenSerial: "RP000000000", certificates: [])
        func cert(_ label: String, from: Double, to: Double) -> PhoneCertRow {
            PhoneCertRow(label: label,
                         summary: TokenCodec.CertSummary(subject: "MARKO PETROVIC", issuer: "MUP Stranci CA 4",
                                                         notBefore: Date().addingTimeInterval(-from * 86400),
                                                         notAfter: Date().addingTimeInterval(to * 86400),
                                                         chainTrusted: true, chainError: nil),
                         der: Data())
        }
        tokenRows = [cert("MARKO PETROVIC 000000000 Auth", from: 420, to: 1040),
                     cert("MARKO PETROVIC 000000000 Sign", from: 420, to: 1040)]
        demoActive = true
    }

    /// Switch the demo data off again.
    func hideDemo() { if demoActive { clear() } }

    private let nfcReader = NFCCardReader()
    private let usbReader = USBCardReader()
    private let loc = Loc.shared

    var nfcAvailable: Bool { Self.nfcEnabled && NFCCardReader.isAvailable }

    /// Wired reader unless NFC is switched on again (`nfcEnabled`).
    var autoSource: ReadSource { USBCardReader.hasReader || !nfcAvailable ? .usb : .nfc }
    var autoIcon: String { autoSource == .usb ? "cable.connector" : "wave.3.right" }

    private let tokenWatcher = TKTokenWatcher()

    /// The system has attached our token driver to the inserted card (this is what Safari needs for the certificate).
    var driverAttached: Bool { tokenWatcher.tokenIDs.contains { $0.hasPrefix("app.supercelik.token") } }

    /// Gives the system a moment to attach the driver before the app takes the card for its own reading.
    private func waitForDriver() async {
        for _ in 0..<8 where !driverAttached { try? await Task.sleep(nanoseconds: 500_000_000) }
    }

    /// Follows the reader while the app is open: plugging it in or inserting a card updates the screens at once.
    func watchReader() async {
        while !Task.isCancelled {
            let now = await USBCardReader.currentState()
            if now != readerState {
                let before = readerState
                readerState = now
                if now == .cardReady || (before == .none && now == .noCard) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                // A card went into the reader (or the app opened with one inserted): read it by itself if the setting is on.
                if now == .cardReady, before != .cardReady, Prefs.shared.autoRead, !busy {
                    await waitForDriver()
                    if activeTab == 1 { await scanTokenAuto() } else { await scanCardAuto() }
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    @discardableResult func scanCardAuto() async -> Bool { await scanCard(autoSource) }
    func scanTokenAuto() async { await scanToken(autoSource) }

    /// Runs the shared card code through the chosen transport (wired reader or NFC).
    private func run<T>(_ source: ReadSource, _ body: @escaping @Sendable (EidCard) throws -> T) async throws -> T {
        switch source {
        case .usb: return try await usbReader.run(body)
        case .nfc: return try await nfcReader.run(prompts: prompts, body)
        }
    }

    private var prompts: NFCCardReader.Prompts {
        .init(start: loc.t(.nfcPrompt), reading: loc.t(.nfcReading), done: loc.t(.nfcDone))
    }

    // MARK: - Reading

    /// One tap: personal data + photo, then both card signatures, in the same NFC session
    /// (EidCard caches the files, so verifying does not read them again).
    /// Returns true only when this call itself read the card (not when another operation was already running).
    @discardableResult
    func scanCard(_ source: ReadSource = .usb) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let (p, status) = try await run(source) { card -> (PersonalData, SigStatus) in
                let p = try card.readPersonalData()
                let status: SigStatus
                do {
                    for s in [EidSignature.fixed, .variable] { _ = try card.verify(signature: s) }
                    status = .ok
                } catch CardError.chainNotTrusted(let m) { status = .chainNotTrusted(m) }
                catch CardError.signature(let m) { status = .invalid(m) }
                catch CardError.unsupportedForCard { status = .unavailable }
                catch let e as NFCProblem { throw e }      // card taken away: report it, not "bad signature"
                catch { status = .invalid(error.localizedDescription) }
                return (p, status)
            }
            personal = p; signatureStatus = status; revealAll = false; problem = nil; demoActive = false
            return true
        } catch { show(error); return false }
    }

    func scanToken(_ source: ReadSource = .usb) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let t = try await run(source) { try $0.readToken() }
            token = t
            tokenRows = t.certificates.map {
                PhoneCertRow(label: $0.label, summary: TokenCodec.summarize(der: $0.der), der: $0.der)
            }
            problem = nil
        } catch { show(error) }
    }

    // MARK: - Token PIN / PUK (a wrong PIN or PUK burns a card try: one attempt, never retried)

    static func validPin(_ p: String) -> Bool {
        (4...8).contains(p.count) && p.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    /// Changes the token PIN (`puk == nil`) or unblocks it with the PUK. Returns true on success.
    @discardableResult
    func pinOperation(secret: String, new: String, confirm: String, unblock: Bool) async -> Bool {
        guard Self.validPin(secret), Self.validPin(new) else { pinAlert = loc.t(.pinInvalid); return false }
        guard new == confirm else { pinAlert = loc.t(.pinMismatch); return false }
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            _ = try await run(autoSource) { card -> Bool in
                if unblock { try card.unblockTokenPin(puk: secret, new: new) }
                else { try card.changeTokenPin(old: secret, new: new) }
                return true
            }
            pinAlert = loc.t(unblock ? .pinUnblocked : .pinChanged)
            return true
        } catch {
            pinAlert = pinMessage(for: error)
        }
        return false
    }

    /// The text shown for a failed PIN / PUK / signing operation.
    private func pinMessage(for error: Error) -> String {
        switch error {
        case CardError.pinWrong(let n): return loc.t(.pinWrongMsg) + "\(n)"
        case CardError.pinBlocked: return loc.t(.pinBlockedMsg)
        case NFCProblem.noReader: return loc.t(.emptyNoReaderT)
        case NFCProblem.noCard: return loc.t(.emptyNoCardT)
        default: return error.localizedDescription
        }
    }

    /// Detached CMS signature (.p7s, SHA-256, token key) over the given file contents. Returns the file to share, or nil
    /// (the reason is in `pinAlert`). A wrong PIN burns a card try: one attempt, never retried.
    func signFile(data: Data, name: String, pin: String) async -> URL? {
        guard Self.validPin(pin) else { pinAlert = loc.t(.pinInvalid); return nil }
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        let noCert = loc.t(.signNeedCert)
        do {
            let p7s = try await run(autoSource) { card -> Data in
                let tok = try card.readToken()
                guard let cert = tok.certificates.first else { throw CardError.signature(noCert) }
                return try CMSBuilder.signDetached(data: data, certDer: cert.der) { di in
                    try card.tokenSign(pin: pin, keyFile: EidCard.defaultSignKeyFile, digestInfo: di)
                }
            }
            let url = temporaryFile(p7s, name: name + ".p7s")
            exportedNames.insert(name + ".p7s")
            pinAlert = nil
            return url
        } catch {
            pinAlert = pinMessage(for: error)
            return nil
        }
    }

    func clear() {
        personal = nil; signatureStatus = nil; token = nil; tokenRows = []; revealAll = false; problem = nil; demoActive = false
    }

    private func show(_ error: Error) {
        switch error {
        case NFCProblem.cancelled:
            return                                   // user closed the sheet: nothing to report
        case NFCProblem.unavailable:
            problem = PhoneProblem(title: .nfcUnavailableT, hint: .nfcUnavailableH)
        case NFCProblem.noReader:
            problem = PhoneProblem(title: .emptyNoReaderT, hint: .iosNoReaderH)
        case NFCProblem.noCard:
            problem = PhoneProblem(title: .emptyNoCardT, hint: .emptyNoCardH)
        case NFCProblem.connectionLost:
            problem = PhoneProblem(title: .nfcLostT, hint: .nfcLostH)
        case CardError.unsupportedForCard:
            problem = PhoneProblem(title: .errUnsupportedT, hint: .errUnsupportedH)
        case NFCProblem.other(let m):
            problem = PhoneProblem(title: .errGenericT, hint: .nfcLostH, tech: m)
        default:
            problem = PhoneProblem(title: .errGenericT, hint: .nfcLostH, tech: error.localizedDescription)
        }
    }

    // MARK: - Export

    /// The MUP printout as a one-page A4 PDF (same layout code as the macOS print).
    func pdfData(includeJmbg: Bool) -> Data? {
        guard let p = personal else { return nil }
        let size = MupPrintLayout.pageSize
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            MupPrintLayout(p, includeJmbg: includeJmbg).draw()
        }
    }

    /// Writes data to a temporary file (for the share sheet).
    func temporaryFile(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url, options: [.atomic, .completeFileProtection]); return url } catch { return nil }
    }

    func pdfFile(includeJmbg: Bool) -> URL? {
        pdfData(includeJmbg: includeJmbg).flatMap { temporaryFile($0, name: "SuperCelik.pdf") }
    }

    func printPDF(includeJmbg: Bool) {
        guard let data = pdfData(includeJmbg: includeJmbg) else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "Super Čelik"
        let pc = UIPrintInteractionController.shared
        pc.printInfo = info
        pc.printingItem = data
        pc.present(animated: true)
    }

    func copyAll() {
        guard let p = personal else { return }
        UIPasteboard.general.string = p.rows().map { "\(loc.t($0.label)): \($0.value)" }.joined(separator: "\n")
    }

    /// The photo as a JPEG file for the share sheet.
    func photoFile() -> URL? {
        guard let d = personal?.portrait else { return nil }
        return temporaryFile(d, name: "photo.jpg")
    }

    /// The card data as a JSON file (same content as the Mac export).
    func jsonFile() -> URL? {
        guard let p = personal else { return nil }
        var obj: [String: String] = ["cardType": String(describing: p.cardType)]
        for r in p.rows() { obj[r.id] = r.value }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return temporaryFile(data, name: "SuperCelik.json")
    }

    /// Names of signature files made in this run (their names depend on the signed file).
    private var exportedNames = Set<String>()

    /// Removes exported files (PDF / certificates / photo / JSON / signatures) from the temporary folder.
    func removeTemporaryFiles() {
        let dir = FileManager.default.temporaryDirectory
        for name in ["SuperCelik.pdf", "certificate.cer", "photo.jpg", "SuperCelik.json"] + Array(exportedNames) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
