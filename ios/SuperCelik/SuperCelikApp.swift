import SwiftUI

@main
struct SuperCelikApp: App {
    @StateObject private var loc = Loc.shared
    @StateObject private var prefs = Prefs.shared
    @StateObject private var model = PhoneModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(loc)
                .environmentObject(prefs)
                .environmentObject(model)
                .preferredColorScheme(prefs.colorScheme)
        }
        .onChange(of: scenePhase) { phase in
            // Privacy: exported PDFs / certificates do not stay in the temporary folder.
            if phase == .background { model.removeTemporaryFiles() }
        }
    }
}
