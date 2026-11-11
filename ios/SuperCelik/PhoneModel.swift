import SwiftUI
import UIKit

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
    @Published var problem: PhoneProblem?

    enum ReadSource { case usb, nfc }

    /// `--demo` launch argument: fictional data for screenshots (never touches a card).
    init() {
        if CommandLine.arguments.contains("--demo") { loadDemo() }
    }

    private func loadDemo() {
        var p = PersonalData()
        p.cardType = .rp2024
        p.document = DocumentData(docRegNo: "001234567", documentType: "RP", issuingDate: "01.01.2024",
                                  expiryDate: "01.01.2026", issuingAuthority: "MUP RS", documentSerialNumber: "RS1234567")
        p.fixed = FixedPersonalData(personalNumber: "0101990710000", surname: "PETROVIĆ", givenName: "MARKO", sex: "M",
                                    stateOfBirth: "Srbija", dateOfBirth: "01.01.1990", nationalityFull: "Srbija")
        p.variable = VariablePersonalData(community: "Stari Grad", place: "Beograd", street: "Knez Mihailova", houseNumber: "1")
        personal = p
        signatureStatus = .ok
    }

    private let nfcReader = NFCCardReader()
    private let usbReader = USBCardReader()
    private let loc = Loc.shared

    var nfcAvailable: Bool { NFCCardReader.isAvailable }

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
    func scanCard(_ source: ReadSource = .usb) async {
        guard !busy else { return }
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
            personal = p; signatureStatus = status; revealAll = false; problem = nil
        } catch { show(error) }
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

    func clear() {
        personal = nil; signatureStatus = nil; token = nil; tokenRows = []; revealAll = false; problem = nil
    }

    private func show(_ error: Error) {
        switch error {
        case NFCProblem.cancelled:
            return                                   // user closed the sheet: nothing to report
        case NFCProblem.unavailable:
            problem = PhoneProblem(title: .nfcUnavailableT, hint: .nfcUnavailableH)
        case NFCProblem.noReader:
            problem = PhoneProblem(title: .usbNoReaderT, hint: .usbNoReaderH)
        case NFCProblem.noCard:
            problem = PhoneProblem(title: .nfcNoCardT, hint: .nfcNoCardH)
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
        info.jobName = "Super Celik"
        let pc = UIPrintInteractionController.shared
        pc.printInfo = info
        pc.printingItem = data
        pc.present(animated: true)
    }

    func copyAll() {
        guard let p = personal else { return }
        UIPasteboard.general.string = p.rows().map { "\(loc.t($0.label)): \($0.value)" }.joined(separator: "\n")
    }

    /// Removes exported files (PDF / certificates) from the temporary folder.
    func removeTemporaryFiles() {
        let dir = FileManager.default.temporaryDirectory
        for name in ["SuperCelik.pdf", "certificate.cer"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
