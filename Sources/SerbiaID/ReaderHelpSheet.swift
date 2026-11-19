import SwiftUI
import WebKit

/// The page about card readers (which one to get, how to connect it), shown inside the app.
struct ReaderHelpSheet: View {
    @EnvironmentObject var loc: Loc
    @Environment(\.dismiss) private var dismiss
    static let url = URL(string: "https://celik.peregon.cc/reader/")!

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t(.readerHelpTitle)).font(.headline)
                Spacer()
                Button(loc.t(.close)) { dismiss() }.keyboardShortcut(.cancelAction).glassButton()
            }
            .padding(12)
            Divider()
            ReaderWebView(url: Self.url)
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 520, idealHeight: 680)
    }
}

private struct ReaderWebView: NSViewRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.uiDelegate = context.coordinator
        w.load(URLRequest(url: url))
        return w
    }
    func updateNSView(_ view: WKWebView, context: Context) {}

    /// The shop links on the page open in a new window (`target="_blank"`): a web view has none, so they go to the default browser.
    final class Coordinator: NSObject, WKUIDelegate {
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = navigationAction.request.url, u.scheme == "https" || u.scheme == "http" { NSWorkspace.shared.open(u) }
            return nil
        }
    }
}
