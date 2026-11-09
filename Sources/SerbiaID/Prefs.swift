import SwiftUI

/// User preferences (UserDefaults).
final class Prefs: ObservableObject {
    static let shared = Prefs()

    @Published var theme: String { didSet { UserDefaults.standard.set(theme, forKey: "theme") } }            // system / light / dark
    @Published var autoUpdate: Bool { didSet { UserDefaults.standard.set(autoUpdate, forKey: "autoUpdate") } }
    @Published var maskSensitive: Bool { didSet { UserDefaults.standard.set(maskSensitive, forKey: "maskSensitive") } }
    @Published var autoRead: Bool { didSet { UserDefaults.standard.set(autoRead, forKey: "autoRead") } }
    @Published var printJmbg: Bool { didSet { UserDefaults.standard.set(printJmbg, forKey: "printJmbg") } }
    @Published var autoHideMinutes: Int { didSet { UserDefaults.standard.set(autoHideMinutes, forKey: "autoHideMinutes") } }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["theme": "system", "autoUpdate": true, "maskSensitive": true,
                              "autoRead": false, "printJmbg": true, "autoHideMinutes": 3])
        theme = d.string(forKey: "theme") ?? "system"
        autoUpdate = d.bool(forKey: "autoUpdate")
        maskSensitive = d.bool(forKey: "maskSensitive")
        autoRead = d.bool(forKey: "autoRead")
        printJmbg = d.bool(forKey: "printJmbg")
        autoHideMinutes = d.integer(forKey: "autoHideMinutes")
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
