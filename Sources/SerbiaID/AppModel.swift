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
