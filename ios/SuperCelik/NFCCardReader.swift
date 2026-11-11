import Foundation
import CoreNFC

/// Why an NFC read ended without a result.
enum NFCProblem: Error {
    case unavailable        // device has no NFC reader, or the app lacks the entitlement
    case cancelled          // user closed the system sheet
    case noCard             // timed out without finding a card we can talk to (or none in the USB reader)
    case noReader           // no USB / Lightning smart card reader visible to the system
    case connectionLost     // card moved away during the read
    case other(String)
}

/// Talks to the card over NFC (ISO 14443 / ISO 7816) and runs the shared protocol code
/// (EidCard, the same code the macOS app runs over a USB reader) inside one NFC session.
///
/// Note: iOS only reports a card if it answers to one of the AIDs listed in Info.plist
/// (com.apple.developer.nfc.readersession.iso7816.select-identifiers).
final class NFCCardReader: NSObject, NFCTagReaderSessionDelegate {
    struct Prompts { var start: String; var reading: String; var done: String }

    static var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    /// Callbacks of the session arrive here; APDU replies too.
    private let sessionQueue = DispatchQueue(label: "supercelik.nfc.session")
    /// The (blocking) protocol code runs here, so it can wait for APDU replies.
    private let workQueue = DispatchQueue(label: "supercelik.nfc.work")

    private var session: NFCTagReaderSession?
    private var prompts = Prompts(start: "", reading: "", done: "")
    private var work: ((EidCard) throws -> Any)?
    private var finish: ((Result<Any, Error>) -> Void)?

    /// Opens the system NFC sheet, waits for a card, runs `body` against it and closes the sheet.
    func run<T>(prompts: Prompts, _ body: @escaping @Sendable (EidCard) throws -> T) async throws -> T {
        let value: Any = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any, Error>) in
            sessionQueue.async {
                guard NFCTagReaderSession.readingAvailable else {
                    cont.resume(throwing: NFCProblem.unavailable); return
                }
                var done = false
                self.finish = { result in            // always called on sessionQueue
                    guard !done else { return }
                    done = true
                    cont.resume(with: result)
                }
                self.work = { try body($0) }
                self.prompts = prompts
                guard let s = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: self.sessionQueue) else {
                    self.complete(.failure(NFCProblem.unavailable)); return
                }
                s.alertMessage = prompts.start
                self.session = s
                s.begin()
            }
        }
        guard let result = value as? T else { throw NFCProblem.other("unexpected result") }
        return result
    }

    private func complete(_ result: Result<Any, Error>) {
        finish?(result)
        finish = nil
        work = nil
        session = nil
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // Also called after a successful read (we invalidate the session); then finish is already nil.
        complete(.failure(Self.map(error)))
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        var found: (tag: NFCTag, card: NFCISO7816Tag)?
        for tag in tags { if case .iso7816(let t) = tag { found = (tag, t); break } }
        guard let found else {
            // Some other NFC tag (bank card, transit card...): keep looking for the ID card.
            session.restartPolling()
            return
        }
        let tag = found.tag, card = found.card
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                session.invalidate(errorMessage: error.localizedDescription)
                self.complete(.failure(Self.map(error)))
                return
            }
            session.alertMessage = self.prompts.reading
            guard let work = self.work else { return }
            self.workQueue.async {
                let eid = EidCard { apdu in try Self.send(apdu, to: card) }
                let result: Result<Any, Error> = Result { try work(eid) }
                self.sessionQueue.async {
                    // Resolve first: invalidating triggers didInvalidateWithError, which must not win.
                    self.complete(result)
                    switch result {
                    case .success:
                        session.alertMessage = self.prompts.done
                        session.invalidate()
                    case .failure(let e):
                        session.invalidate(errorMessage: e.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: APDU transport

    /// Sends one APDU and blocks until the reply arrives (called on workQueue only).
    private static func send(_ apdu: [UInt8], to tag: NFCISO7816Tag) throws -> EidCard.Response {
        guard let command = NFCISO7816APDU(data: Data(apdu)) else { throw CardError.transport("Invalid APDU") }
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<EidCard.Response, Error> = .failure(NFCProblem.connectionLost)
        tag.sendCommand(apdu: command) { data, sw1, sw2, error in
            if let error {
                result = .failure(Self.map(error))
            } else {
                result = .success(([UInt8](data), UInt16(sw1) << 8 | UInt16(sw2)))
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 15) == .timedOut { throw NFCProblem.connectionLost }
        return try result.get()
    }

    private static func map(_ error: Error) -> Error {
        if error is NFCProblem || error is CardError { return error }
        guard let e = error as? NFCReaderError else { return NFCProblem.other(error.localizedDescription) }
        switch e.code {
        case .readerSessionInvalidationErrorUserCanceled:
            return NFCProblem.cancelled
        case .readerSessionInvalidationErrorSessionTimeout:
            return NFCProblem.noCard
        case .readerTransceiveErrorTagConnectionLost, .readerTransceiveErrorTagResponseError,
             .readerTransceiveErrorRetryExceeded, .readerTransceiveErrorTagNotConnected:
            return NFCProblem.connectionLost
        case .readerErrorUnsupportedFeature, .readerErrorSecurityViolation, .readerErrorInvalidParameter:
            return NFCProblem.unavailable
        default:
            return NFCProblem.other(e.localizedDescription)
        }
    }
}
