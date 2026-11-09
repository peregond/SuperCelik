import SwiftUI

@main
struct SerbiaIDApp: App {
    @StateObject private var loc = Loc.shared
    @StateObject private var prefs = Prefs.shared
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(loc)
                .environmentObject(prefs)
                .environmentObject(model)
                .preferredColorScheme(prefs.colorScheme)
                .frame(minWidth: 860, minHeight: 600)
        }
        .commands {
            CommandMenu(loc.t(.language)) {
                ForEach(AppLanguage.allCases) { lang in
                    Button(lang.title) { loc.language = lang }
                }
            }
        }
    }
}
