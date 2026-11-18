import SwiftUI
import UIKit

/// Home Screen quick actions (long press on the app icon). Titles and icons are the ones the app already uses.
enum QuickAction: String {
    case readCard = "app.supercelik.action.read"
    case printCard = "app.supercelik.action.print"
    case loginEuprava = "app.supercelik.action.login"
}

@MainActor
final class QuickActions: ObservableObject {
    static let shared = QuickActions()
    /// Set by the scene delegate; the root view takes it and clears it.
    @Published var pending: QuickAction?

    /// Dynamic shortcuts follow the language chosen in the app.
    func publish() {
        let loc = Loc.shared
        func item(_ a: QuickAction, _ title: Loc.L, _ symbol: String) -> UIApplicationShortcutItem {
            UIApplicationShortcutItem(type: a.rawValue, localizedTitle: loc.t(title), localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: symbol), userInfo: nil)
        }
        UIApplication.shared.shortcutItems = [
            item(.readCard, .readCardAuto, "person.text.rectangle"),
            item(.printCard, .printCard, "printer"),
            item(.loginEuprava, .loginEuprava, "person.badge.key"),
        ]
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem, let action = QuickAction(rawValue: item.type) {
            Task { @MainActor in QuickActions.shared.pending = action }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// App already running: the user picked an action from the icon.
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        guard let action = QuickAction(rawValue: shortcutItem.type) else { completionHandler(false); return }
        Task { @MainActor in QuickActions.shared.pending = action }
        completionHandler(true)
    }
}
