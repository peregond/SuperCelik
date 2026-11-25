import SwiftUI

@main
struct SerbiaIDApp: App {
    @StateObject private var loc = Loc.shared
    @StateObject private var prefs = Prefs.shared
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(ShotDelegate.self) private var shotDelegate

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
            // Card actions live in the menu bar too, so their shortcuts work even when the
            // toolbar has moved a button into its overflow menu.
            CommandMenu(loc.t(.menuCard)) {
                Button(loc.t(.readCard)) { Task { await model.readCard() } }
                    .keyboardShortcut("r").disabled(!model.cardPresent || model.busy)
                Button(loc.t(.verifySignature)) { Task { await model.verifySignatures() } }
                    .disabled(!model.cardPresent || model.busy)
                Divider()
                Button(loc.t(.printCard)) { model.showPreview = true }
                    .keyboardShortcut("p").disabled(model.personal == nil && model.vehicle == nil)
                Button(loc.t(.savePdf)) { model.savePDF(loc: loc, includeJmbg: prefs.printJmbg) }
                .keyboardShortcut("s").disabled(model.personal == nil && model.vehicle == nil)
            }
            CommandMenu(loc.t(.language)) {
                ForEach(AppLanguage.pickerTop) { lang in
                    Button(loc.pickerLabel(lang)) { loc.language = lang }
                }
                Divider()
                ForEach(AppLanguage.pickerRest) { lang in
                    Button(loc.pickerLabel(lang)) { loc.language = lang }
                }
            }
        }
    }
}
