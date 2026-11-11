import Foundation
import AppKit
import CryptoKit

struct UpdateInfo {
    let version: String
    let assetURL: URL
    let sha256: String?
    let pageURL: URL
}

#if !APPSTORE
/// Checks the latest GitHub release and installs it. Works only while the release is readable
/// without authentication (public repository). Downloads are restricted to GitHub hosts and
/// verified against the SHA-256 digest published by GitHub when available.
enum Updater {
    static let repo = "peregond/SuperCelik"

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    #if arch(arm64)
    static let assetSuffix = "-macOS-apple-silicon.dmg"
    #else
    static let assetSuffix = "-macOS-intel.dmg"
    #endif

    private static func numeric(_ s: String) -> [Int]? {
        guard let r = s.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) else { return nil }
        return s[r].split(separator: ".").compactMap { Int($0) }
    }

    private static func isNewer(_ remote: [Int], than local: [Int]) -> Bool {
        for (a, b) in zip(remote, local) where a != b { return a > b }
        return false
    }

    private static func trusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let h = url.host else { return false }
        return h == "github.com" || h.hasSuffix(".github.com") || h.hasSuffix(".githubusercontent.com")
    }

    /// `info == nil && reachable` means up to date; `reachable == false` means no release info (offline / private repo).
    static func check() async -> (info: UpdateInfo?, reachable: Bool) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return (nil, false) }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("SuperCelik-updater", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return (nil, false) }

        guard let remote = numeric(tag), let local = numeric(currentVersion), isNewer(remote, than: local) else {
            return (nil, true)
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let a = assets.first(where: { ($0["name"] as? String)?.hasSuffix(assetSuffix) == true }),
              let s = a["browser_download_url"] as? String, let assetURL = URL(string: s), trusted(assetURL),
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return (nil, true) }
        var sha: String?
        if let d = a["digest"] as? String, d.hasPrefix("sha256:") { sha = String(d.dropFirst(7)) }
        return (UpdateInfo(version: remote.map(String.init).joined(separator: "."),
                           assetURL: assetURL, sha256: sha, pageURL: page), true)
    }

    enum UpdateError: LocalizedError {
        case checksum, untrusted
        var errorDescription: String? {
            switch self {
            case .checksum: return "Checksum mismatch: download rejected"
            case .untrusted: return "Untrusted download URL"
            }
        }
    }

    /// Downloads the .dmg, verifies it, replaces the running .app and relaunches it.
    /// If the app is not in a writable location the .dmg is just opened (drag to Applications).
    @MainActor static func install(_ info: UpdateInfo) async throws {
        guard trusted(info.assetURL) else { throw UpdateError.untrusted }
        let (tmp, _) = try await URLSession.shared.download(from: info.assetURL)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SuperCelikUpdate")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dmg = dir.appendingPathComponent(info.assetURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dmg)
        try FileManager.default.moveItem(at: tmp, to: dmg)

        if let want = info.sha256 {
            let got = SHA256.hash(data: try Data(contentsOf: dmg)).map { String(format: "%02x", $0) }.joined()
            guard got.lowercased() == want.lowercased() else { try? FileManager.default.removeItem(at: dmg); throw UpdateError.checksum }
        }

        let app = Bundle.main.bundleURL
        let writable = app.pathExtension == "app" &&
            FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
        guard writable else { NSWorkspace.shared.open(dmg); return }

        let script = dir.appendingPathComponent("install.sh")
        try """
        #!/bin/sh
        # $1 = dmg, $2 = destination .app
        sleep 1
        MNT=$(mktemp -d /tmp/supercelik.XXXXXX)
        hdiutil attach -nobrowse -quiet -mountpoint "$MNT" "$1" || exit 1
        NEW=$(ls -d "$MNT"/*.app | head -n 1)
        rm -rf "$2" && cp -R "$NEW" "$2"
        xattr -dr com.apple.quarantine "$2"
        hdiutil detach -quiet "$MNT"
        open "$2"
        """.write(to: script, atomically: true, encoding: .utf8)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, dmg.path, app.path]
        try p.run()
        NSApp.terminate(nil)
    }
}
#else
/// Mac App Store build: updates come from the store, so there is no updater (and no network code).
enum Updater {
    static var currentVersion: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0" }
    static func check() async -> (info: UpdateInfo?, reachable: Bool) { (nil, true) }
    @MainActor static func install(_ info: UpdateInfo) async throws {}
}
#endif
