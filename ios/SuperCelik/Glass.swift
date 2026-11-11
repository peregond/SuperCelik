import SwiftUI
import QuickLook

// Liquid Glass (iOS 26 design). Everything is guarded twice: `#if compiler(>=6.2)` keeps the file compiling with
// Xcode older than 26, and `#available(iOS 26.0, *)` falls back to regular materials on older iOS.

extension View {
    /// A card with a Liquid Glass surface (material on older systems).
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 26) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    /// Glass button style (prominent = tinted), bordered styles on older systems.
    @ViewBuilder func glassButton(prominent: Bool) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
        #else
        if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        #endif
    }

    /// iOS 26: the tab bar shrinks while scrolling down.
    @ViewBuilder func minimizingTabBar() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { self.tabBarMinimizeBehavior(.onScrollDown) } else { self }
        #else
        self
        #endif
    }
}

/// Groups glass shapes so they blend into each other (iOS 26), plain container before.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { VStack(spacing: spacing, content: content) }
        } else {
            VStack(spacing: spacing, content: content)
        }
        #else
        VStack(spacing: spacing, content: content)
        #endif
    }
}

/// Soft flag-coloured backdrop (navy at the top, a touch of red below): gives the glass something to refract.
struct GlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [Color(red: 0.05, green: 0.25, blue: 0.46).opacity(scheme == .dark ? 0.55 : 0.28),
                                    Color(red: 0.78, green: 0.21, blue: 0.24).opacity(scheme == .dark ? 0.30 : 0.14),
                                    .clear],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// Tricolour accent (red, blue, white) used above the name card.
struct FlagStripe: View {
    var body: some View {
        HStack(spacing: 0) {
            Color(red: 0.78, green: 0.21, blue: 0.24)
            Color(red: 0.05, green: 0.25, blue: 0.46)
            Color(white: 0.92)
        }
        .frame(height: 5)
        .clipShape(Capsule())
    }
}

/// System Quick Look: shows the PDF with the system's own share and print buttons.
struct PDFPreview: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UINavigationController {
        let q = QLPreviewController()
        q.dataSource = context.coordinator
        return UINavigationController(rootViewController: q)
    }
    func updateUIViewController(_ vc: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
