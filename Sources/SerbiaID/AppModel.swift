import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var readers: [String] = []
    @Published var selectedReader = ""
    @Published var atrHex: String?
    @Published var cardPresent = false
    @Published var personal: PersonalData?
    @Published var certificates: [CertificateInfo] = []
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private(set) var service: CardService
    let useDemo: Bool

    init() {
        useDemo = ProcessInfo.processInfo.environment["SERBIAID_DEMO"] == "1"
        service = useDemo ? MockCardService() : PCSCService()
        refresh()
    }

    func refresh() {
        do {
            readers = try service.listReaders()
            if !readers.contains(selectedReader) { selectedReader = readers.first ?? "" }
            guard !selectedReader.isEmpty else { cardPresent = false; atrHex = nil; return }
            if let atr = try service.atr(reader: selectedReader) {
                cardPresent = true
                atrHex = atr.map { String(format: "%02X", $0) }.joined(separator: " ")
            } else { cardPresent = false; atrHex = nil }
        } catch { errorMessage = error.localizedDescription }
    }

    func readCard() {
        do {
            personal = try service.readPersonalData(reader: selectedReader)
            certificates = try service.readCertificates(reader: selectedReader,
                                                        cardType: personal?.cardType ?? .id2014)
        } catch { errorMessage = error.localizedDescription }
    }

    struct TokenCertRow: Identifiable {
        let id: UUID
        let label: String
        let summary: TokenCodec.CertSummary?
    }
    @Published var token: TokenInfo?
    @Published var tokenRows: [TokenCertRow] = []

    /// Read-only: no PIN is sent to the card.
    func readToken() {
        do {
            let t = try service.readToken(reader: selectedReader)
            token = t
            tokenRows = t.certificates.map {
                TokenCertRow(id: $0.id, label: $0.label, summary: TokenCodec.summarize(der: $0.der))
            }
        } catch CardError.unsupportedForCard { token = nil; tokenRows = []; errorMessage = "No token applet on this card" }
        catch { errorMessage = error.localizedDescription }
    }

    @Published var update: UpdateInfo?
    @Published var updating = false
    @Published var updateStatus: String?

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
        catch { errorMessage = "\(Loc.shared.t(.updateFailed)): \(error.localizedDescription)" }
        updating = false
    }

    enum SigStatus { case ok, chainNotTrusted(String), invalid(String), unavailable }
    @Published var signatureStatus: SigStatus?

    func verifySignatures() {
        do {
            for s in [EidSignature.fixed, .variable] {
                _ = try service.verify(reader: selectedReader, signature: s)
            }
            signatureStatus = .ok
        } catch CardError.chainNotTrusted(let m) { signatureStatus = .chainNotTrusted(m) }
        catch CardError.signature(let m) { signatureStatus = .invalid(m) }
        catch CardError.notImplemented, CardError.unsupportedForCard { signatureStatus = .unavailable }
        catch { errorMessage = error.localizedDescription }
    }

    /// Returns remaining tries. Only the old (Apollo) card supports this via the official API.
    var canChangePin: Bool { personal?.cardType == .id2008 }

    func changePin(old: String, new: String) throws -> Int {
        try service.changePin(reader: selectedReader, cardType: personal?.cardType ?? .id2014, old: old, new: new)
    }
}
