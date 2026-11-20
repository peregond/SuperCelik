import Foundation

/// Firefox on macOS takes client certificates from the keychain, the same place Chrome and Safari use and where the card driver (the
/// CryptoTokenKit extension, see BrowserLogin.swift) makes the card certificate appear, so Firefox needs no module of its own: since
/// version 90 it does that by default. This looks at the Firefox profiles for the one case where it does not (the preference turned
/// off) and turns it on, when the user agrees. Nothing else in Firefox is touched.
/// The Mac App Store build is sandboxed and cannot see Firefox's files, so there it never finds anything.
/// Same logic as windows/SerbiaID.Windows/FirefoxProfiles.cs.
enum FirefoxSetup {
    static let pref = "security.osclientcerts.autoload"
    static let minMajor = 75          // the first Firefox that can use the keychain certificates at all (before 90 only with the preference on)

    struct Profile {
        var url: URL
        var major: Int                // the Firefox version this profile was last started with, 0 = unknown
    }

    struct Status {
        var profiles = 0              // 0 = no Firefox profile found (not installed, or never started)
        var disabled: [Profile] = []  // the preference is off in these: it can be turned on
        var oldMajor = 0              // every profile is older than Firefox 75, which cannot use keychain certificates at all: the newest version seen (0 = no such case)
    }

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Firefox", isDirectory: true)
    }

    static func check() -> Status {
        #if APPSTORE
        return Status()
        #else
        var status = Status()
        var tooOld = 0, newest = 0
        for p in findProfiles(root: root) {
            status.profiles += 1
            if p.major > 0 && p.major < minMajor {
                tooOld += 1
                newest = max(newest, p.major)
            } else if readBoolPref(p.url, pref) == false {
                status.disabled.append(p)
            }
        }
        // an old profile next to a current one is just an abandoned profile: only report it when nothing else is left
        if tooOld > 0 && tooOld == status.profiles { status.oldMajor = newest }
        return status
        #endif
    }

    /// Turns the preference on where it is off. Returns how many profiles were changed.
    static func enable(_ status: Status) -> Int {
        status.disabled.filter { setBoolPref($0.url, pref, true) }.count
    }

    // MARK: - Profiles

    /// Every profile of the Firefox data folder `root` (the folder that holds profiles.ini): the ones profiles.ini lists, wherever they
    /// live, and the folders that look like a profile (in Profiles/, where macOS keeps them).
    static func findProfiles(root: URL) -> [Profile] {
        let fm = FileManager.default
        var seen = Set<String>()
        var found: [Profile] = []

        func add(_ url: URL) {
            let dir = url.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue, seen.insert(dir.path).inserted else { return }
            found.append(Profile(url: dir, major: readMajor(dir)))
        }

        if let text = readText(root.appendingPathComponent("profiles.ini")) {
            for section in parseIni(text) {
                let name = section.name.lowercased()
                if name.hasPrefix("profile"), let path = section.values["path"], !path.isEmpty {
                    let relative = (section.values["isrelative"] ?? "1") != "0"
                    add(relative ? root.appendingPathComponent(path) : URL(fileURLWithPath: path))
                } else if name.hasPrefix("install"), let path = section.values["default"], !path.isEmpty {
                    add(root.appendingPathComponent(path))          // always relative to the data folder
                }
            }
        }
        for parent in [root, root.appendingPathComponent("Profiles", isDirectory: true)] {
            guard let names = try? fm.contentsOfDirectory(atPath: parent.path) else { continue }
            for name in names.sorted() {
                let dir = parent.appendingPathComponent(name, isDirectory: true)
                if looksLikeProfile(dir) { add(dir) }
            }
        }
        return found
    }

    private static func looksLikeProfile(_ dir: URL) -> Bool {
        ["prefs.js", "cert9.db", "compatibility.ini"].contains { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

    private struct IniSection {
        var name: String
        var values: [String: String] = [:]      // keys in lower case
    }

    private static func parseIni(_ text: String) -> [IniSection] {
        var sections: [IniSection] = []
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append(IniSection(name: String(line.dropFirst().dropLast())))
                continue
            }
            guard !sections.isEmpty, let eq = line.firstIndex(of: "="), eq != line.startIndex else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            sections[sections.count - 1].values[key] = value
        }
        return sections
    }

    /// The Firefox version this profile was last started with, from compatibility.ini ("LastVersion=147.0_2025…/…"). 0 = unknown.
    static func readMajor(_ dir: URL) -> Int {
        guard let text = readText(dir.appendingPathComponent("compatibility.ini")) else { return 0 }
        let key = "lastversion="
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix(key) else { continue }
            let digits = line.dropFirst(key.count).prefix { $0.isASCII && $0.isNumber }
            return Int(digits) ?? 0
        }
        return 0
    }

    // MARK: - Preferences: prefs.js (written by Firefox) and user.js (ours to write; applied at every start, wins over prefs.js)

    private static func prefRegex(_ name: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: "^\\s*user_pref\\(\\s*\"" + NSRegularExpression.escapedPattern(for: name) + "\"\\s*,\\s*([^)]*?)\\s*\\)\\s*;")
    }

    /// The value of `user_pref("name", value);` on this line, nil when the line sets another preference.
    private static func prefValue(_ line: String, _ re: NSRegularExpression) -> String? {
        guard let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(m.range(at: 1), in: line) else { return nil }
        return String(line[r])
    }

    /// The value a boolean preference will have at the next start of Firefox, or nil when no file sets it (Firefox then uses its default).
    static func readBoolPref(_ dir: URL, _ name: String) -> Bool? {
        guard let re = prefRegex(name) else { return nil }
        var result: Bool?
        for file in ["prefs.js", "user.js"] {                       // later wins: user.js is applied after prefs.js
            guard let text = readText(dir.appendingPathComponent(file)) else { continue }
            for line in lines(text) {
                guard let value = prefValue(line, re) else { continue }
                switch value {
                case "true": result = true
                case "false": result = false
                default: result = nil                                   // not a boolean: leave it to Firefox
                }
            }
        }
        return result
    }

    /// Writes `user_pref("name", value);` into the profile's user.js (replacing a line that sets it, keeping every other line).
    /// Takes effect when Firefox starts the next time. Returns false when the file could not be written.
    @discardableResult
    static func setBoolPref(_ dir: URL, _ name: String, _ value: Bool) -> Bool {
        guard let re = prefRegex(name) else { return false }
        let file = dir.appendingPathComponent("user.js")
        let text = readText(file) ?? ""
        let nl = text.contains("\r\n") ? "\r\n" : "\n"
        let wanted = "user_pref(\"\(name)\", \(value ? "true" : "false"));"
        var all = lines(text)
        if all.last == "" { all.removeLast() }                      // the file's final newline
        var out: [String] = []
        var replaced = false
        for line in all {
            if prefValue(line, re) == nil { out.append(line); continue }
            if !replaced { out.append(wanted); replaced = true }    // a duplicate of the same preference is dropped
        }
        if !replaced { out.append(wanted) }
        let result = out.joined(separator: nl) + nl
        if result == text { return true }
        do {
            try result.write(to: file, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    }

    private static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), var text = String(data: data, encoding: .utf8) else { return nil }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }
}
