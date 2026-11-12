import AppKit
import SwiftUI

/// `SuperCelik --shot out.png [personal|token|settings|about] [--dark] [--problem] [--state ...]`
/// Renders the main window with FICTIONAL demo data to a PNG, then quits (used in CI to review the UI).
///
/// The window is built by hand rather than taken from the SwiftUI scene: on a CI runner the scene's
/// window is never opened, so nothing would be drawn.
enum Shot {
    static var arguments: (path: String, page: String)? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--shot"), i + 1 < a.count else { return nil }
        let page = i + 2 < a.count && !a[i + 2].hasPrefix("--") ? a[i + 2] : "personal"
        return (a[i + 1], page)
    }

    /// The page the screenshot asks for (nil in a normal launch).
    static var page: String? { arguments?.page }

    private static var window: NSWindow?

    @MainActor static func run() async {
        guard let req = arguments else { return }
        func log(_ m: String) { FileHandle.standardError.write(Data("shot: \(m)\n".utf8)) }
        log("start \(req.page)")
        let prefs = Prefs.shared
        let root = ContentView()
            .environmentObject(Loc.shared)
            .environmentObject(prefs)
            .environmentObject(AppModel())
            .preferredColorScheme(prefs.colorScheme)
        let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1100, height: 760),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        w.contentView = NSHostingView(rootView: root)
        w.setContentSize(NSSize(width: 1100, height: 760))
        window = w
        NSApp.setActivationPolicy(.regular)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // the frame view includes the title bar and toolbar; fall back to the content alone
        let view: NSView? = w.contentView?.superview ?? w.contentView
        if let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: req.path))
            log("written")
        } else {
            log("nothing to draw")
        }
        // cacheDisplay misses scroll views and glass materials: let the caller take a real window capture
        // (`screencapture -l <id>`), then quit when it says so or after a few seconds
        try? "\(w.windowNumber)".write(toFile: req.path + ".wid", atomically: true, encoding: .utf8)
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: req.path + ".done") {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        // exit() rather than NSApp.terminate: nothing to save, and terminate can wait on the window server in CI
        exit(0)
    }
}

/// Starts the screenshot once the app has launched. Does nothing in a normal launch.
final class ShotDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Shot.arguments != nil else { return }
        Task { @MainActor in await Shot.run() }
    }
}
