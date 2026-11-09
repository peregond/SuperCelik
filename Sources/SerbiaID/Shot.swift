import AppKit

/// `SuperCelik --shot out.png [personal|token|settings|about] [--dark] [--problem]`
/// Renders the main window with FICTIONAL demo data to a PNG, then quits (used in CI to review the UI).
enum Shot {
    static var arguments: (path: String, page: String)? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--shot"), i + 1 < a.count else { return nil }
        let page = i + 2 < a.count && !a[i + 2].hasPrefix("--") ? a[i + 2] : "personal"
        return (a[i + 1], page)
    }

    @MainActor static func runIfRequested(setPage: (String) -> Void) async {
        guard let req = arguments else { return }
        setPage(req.page)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        guard let window = NSApp.windows.first(where: { $0.contentView != nil }), let view = window.contentView else {
            NSApp.terminate(nil); return
        }
        window.setContentSize(NSSize(width: 1100, height: 760))
        try? await Task.sleep(nanoseconds: 800_000_000)
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: req.path))
        }
        NSApp.terminate(nil)
    }
}
