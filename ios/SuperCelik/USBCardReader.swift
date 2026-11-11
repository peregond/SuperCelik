import Foundation
import CryptoTokenKit

/// Reads the card through a wired USB / Lightning smart card reader using the system's CryptoTokenKit
/// (TKSmartCard), then runs the same shared protocol code (EidCard) as the NFC and Mac readers.
///
/// UNVERIFIED on hardware: iOS only hands a reader to the app if the system supports that reader
/// (USB-C iPhone 15+ / iPad with a CCID reader, or an MFi reader). If the system exposes no reader,
/// `run` throws NFCProblem.noReader and the UI points the user to NFC.
final class USBCardReader {
    /// A reader is currently visible to the system.
    static var hasReader: Bool { !(TKSmartCardSlotManager.default?.slotNames.isEmpty ?? true) }

    func run<T>(_ body: @escaping @Sendable (EidCard) throws -> T) async throws -> T {
        guard let manager = TKSmartCardSlotManager.default, let name = manager.slotNames.first else {
            throw NFCProblem.noReader
        }
        guard let slot = await manager.getSlot(withName: name) else { throw NFCProblem.noReader }
        guard slot.state == .validCard, let card = slot.makeSmartCard() else { throw NFCProblem.noCard }
        card.cla = 0x00
        return try await Task.detached(priority: .userInitiated) { () throws -> T in
            try Self.session(card) {
                let eid = EidCard { apdu in try Self.transmit(card, apdu) }
                return try body(eid)
            }
        }.value
    }

    /// Exclusive card session: beginSession ... endSession. Blocking (runs off the main thread).
    private static func session<T>(_ card: TKSmartCard, _ work: () throws -> T) throws -> T {
        let done = DispatchSemaphore(value: 0)
        var ok = false
        card.beginSession { success, _ in ok = success; done.signal() }
        if done.wait(timeout: .now() + 15) == .timedOut { throw NFCProblem.connectionLost }
        guard ok else { throw NFCProblem.noCard }
        defer { card.endSession() }
        return try work()
    }

    /// One APDU; follows T=0 "61xx" (GET RESPONSE) and "6Cxx" (wrong Le).
    private static func transmit(_ card: TKSmartCard, _ apdu: [UInt8]) throws -> EidCard.Response {
        var (data, sw) = try raw(card, apdu)
        if sw >> 8 == 0x6C, apdu.count >= 5 {
            var again = apdu
            again[again.count - 1] = UInt8(sw & 0xFF)
            (data, sw) = try raw(card, again)
        }
        while sw >> 8 == 0x61 {
            let (more, sw2) = try raw(card, [0x00, 0xC0, 0x00, 0x00, UInt8(sw & 0xFF)])
            data += more
            sw = sw2
        }
        return (data, sw)
    }

    private static func raw(_ card: TKSmartCard, _ apdu: [UInt8]) throws -> EidCard.Response {
        let done = DispatchSemaphore(value: 0)
        var reply: Data?
        var failed = false
        card.transmit(Data(apdu)) { r, e in reply = r; failed = e != nil; done.signal() }
        if done.wait(timeout: .now() + 15) == .timedOut || failed { throw NFCProblem.connectionLost }
        guard let reply, reply.count >= 2 else { throw NFCProblem.connectionLost }
        let n = reply.count
        return ([UInt8](reply.prefix(n - 2)), UInt16(reply[reply.startIndex + n - 2]) << 8 | UInt16(reply[reply.startIndex + n - 1]))
    }
}
