import Foundation

/// What "Copy logs and errors" in Settings puts on the clipboard: the technical side of what went wrong (error codes and
/// messages) with the time, the app version and the system. Kept in memory only (since the app started), and it holds no
/// personal data from the card: errors are written without it.
enum DiagLog {
    private static let lock = NSLock()
    private static var lines: [String] = []
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()

    static func add(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append("\(stamp.string(from: Date()))  \(text)")
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
    }

    static func error(_ error: Error, where place: String? = nil) {
        let e = error as NSError
        add("ERROR \(place.map { $0 + ": " } ?? "")\(e.localizedDescription) [\(e.domain) \(e.code)]")
    }

    /// `state`: what the app knows (readers, card present, ...), written by the caller.
    static func report(version: String, language: String, state: String) -> String {
        lock.lock(); defer { lock.unlock() }
        var out = ["Super Čelik \(version)", "System: \(ProcessInfo.processInfo.operatingSystemVersionString)", "Language: \(language)"]
        if !state.isEmpty { out.append(state) }
        out.append("Time: \(stamp.string(from: Date()))")
        out.append("")
        out.append(contentsOf: lines.isEmpty ? ["(no errors since the app started)"] : lines)
        return out.joined(separator: "\n")
    }
}
