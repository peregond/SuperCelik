import SwiftUI

@main
struct SerbiaIDApp: App {
    @StateObject private var loc = Loc.shared
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(loc)
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 520)
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
