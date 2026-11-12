import SwiftUI

/// What the card reader "feels". Drives which pose the mascots take.
enum ReaderMood: Equatable {
    case noReader    // nothing plugged in
    case waiting     // reader connected, no card
    case ready       // card inserted
    case busy        // reading
    case error       // the last operation failed
}

/// The two cartoon characters: the card reader and the token's key.
enum MascotCharacter: String {
    case reader, key

    /// The pose file (Resources/Mascots/<character>-<pose>.png) for a state.
    func pose(for mood: ReaderMood) -> String {
        switch (self, mood) {
        case (_, .noReader): return "sad"
        case (_, .waiting): return "present"
        case (.reader, .ready), (.reader, .busy): return "card"
        case (.key, .ready): return "thumbs"
        case (.key, .busy): return "look"
        case (_, .error): return "worry"
        }
    }
}

/// A mascot drawn from illustrated poses, animated with cheap transforms only:
/// a slow breathing sway, a hop when something good happens, a quick rocking while busy, a shake on errors,
/// and a soft cross-fade between poses. Poses that have no picture yet fall back to the greeting pose, dimmed.
///
/// Nothing animates while the window is inactive or when Reduce Motion is on.
struct MascotArt: View {
    let character: MascotCharacter
    let mood: ReaderMood
    var size: CGFloat = 170

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var phase = false
    @State private var hop: CGFloat = 0
    @State private var shakes: CGFloat = 0

    private var animates: Bool { !reduceMotion && activeState != .inactive }

    private struct Resolved { let name: String; let image: NSImage?; let dim: Bool }
    private var resolved: Resolved {
        let wanted = character.pose(for: mood)
        if let img = Self.image(character, wanted) { return Resolved(name: wanted, image: img, dim: false) }
        return Resolved(name: "present", image: Self.image(character, "present"), dim: true)
    }

    /// sway amplitude (degrees) and half-period (seconds) per state
    private var sway: (deg: Double, secs: Double) {
        switch mood {
        case .busy: return (3.2, 0.32)
        case .ready: return (1.6, 0.9)
        case .noReader: return (0.8, 2.2)
        default: return (1.3, 1.4)
        }
    }

    var body: some View {
        let r = resolved
        let tilt: Double = r.dim ? (mood == .noReader ? -5 : 4) : 0
        ZStack {
            if let img = r.image {
                Image(nsImage: img)
                    .resizable().interpolation(.high).scaledToFit()
                    .saturation(r.dim ? 0.12 : 1).opacity(r.dim ? 0.8 : 1)
                    .id(r.name + (r.dim ? "-dim" : ""))
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(tilt + (phase ? sway.deg : -sway.deg)), anchor: .bottom)
        .scaleEffect(x: 1, y: (phase ? 1.014 : 1) * (r.dim && mood == .noReader ? 0.96 : 1), anchor: .bottom)
        .offset(y: hop)
        .modifier(MascotShake(animatableData: shakes))
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.7), value: r.name)
        .accessibilityHidden(true)
        .onChange(of: mood) { react(to: $0) }
        .task(id: "\(mood)-\(animates)") {
            // restart the loop when the state changes (the period changes with it)
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { phase = false }
            guard animates else { return }
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.easeInOut(duration: sway.secs).repeatForever(autoreverses: true)) { phase = true }
        }
    }

    private func react(to mood: ReaderMood) {
        guard !reduceMotion else { return }
        if mood == .ready {
            Task { @MainActor in   // a little hop
                withAnimation(.easeOut(duration: 0.16)) { hop = -14 }
                try? await Task.sleep(nanoseconds: 160_000_000)
                withAnimation(.interpolatingSpring(stiffness: 260, damping: 12)) { hop = 0 }
            }
        }
        if mood == .error { withAnimation(.linear(duration: 0.45)) { shakes += 1 } }
    }

    // MARK: - pictures

    private static var cache: [String: NSImage] = [:]
    static func image(_ character: MascotCharacter, _ pose: String) -> NSImage? {
        let key = "\(character.rawValue)-\(pose)"
        if let img = cache[key] { return img }
        guard let url = SignatureVerifier.resourceBundle?.url(forResource: key, withExtension: "png", subdirectory: "Resources/Mascots"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[key] = img
        return img
    }
}

/// A short horizontal shake (three swings), used once when something fails.
struct MascotShake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(animatableData * .pi * 6), y: 0))
    }
}
