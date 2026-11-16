import SwiftUI
import UIKit

/// The cartoon reader and key mascots (the same pictures as on the Mac), animated with cheap transforms only:
/// a slow breathing sway, a quicker rocking while busy and a short shake on errors. Nothing moves when
/// Reduce Motion is on.
struct PhoneMascot: View {
    enum Character: String { case reader, key }
    enum Mood: Equatable { case noReader, waiting, ready, busy, error, done }

    let character: Character
    let mood: Mood
    var size: CGFloat = 190

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false
    @State private var shakes: CGFloat = 0
    @State private var hop: CGFloat = 0

    /// Pose files (Mascots/<character>-<pose>.png) for a mood, best first.
    private var poses: [String] {
        switch (character, mood) {
        case (_, .noReader): return ["sad", "worry"]
        case (_, .waiting): return ["present"]
        case (.reader, .ready), (.reader, .busy), (.reader, .done): return ["card"]
        case (.key, .ready): return ["thumbs"]
        case (.key, .busy): return ["look"]
        case (.key, .done): return ["thumbs"]
        case (_, .error): return ["worry", "sad"]
        }
    }

    private var sway: (deg: Double, secs: Double) { mood == .busy ? (3.2, 0.32) : (1.4, 1.4) }

    var body: some View {
        Group {
            if let img = Self.image(character, poses) {
                Image(uiImage: img).resizable().interpolation(.high).scaledToFit()
                    .id(poses.first)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(phase ? sway.deg : -sway.deg), anchor: .bottom)
        .scaleEffect(x: 1, y: phase ? 1.014 : 1, anchor: .bottom)
        .offset(y: hop)
        .modifier(PhoneShake(animatableData: shakes))
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.7), value: poses.first)
        .accessibilityHidden(true)
        .onChange(of: mood) { new in
            guard !reduceMotion else { return }
            if new == .error { withAnimation(.linear(duration: 0.45)) { shakes += 1 } }
            if new == .ready || new == .waiting {   // a reader or a card appeared: a little hop
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.16)) { hop = -16 }
                    try? await Task.sleep(nanoseconds: 160_000_000)
                    withAnimation(.interpolatingSpring(stiffness: 260, damping: 12)) { hop = 0 }
                }
            }
        }
        .task(id: "\(mood)-\(reduceMotion)") {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { phase = false }
            guard !reduceMotion else { return }
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.easeInOut(duration: sway.secs).repeatForever(autoreverses: true)) { phase = true }
        }
    }

    private static var cache: [String: UIImage] = [:]
    private static func image(_ character: Character, _ poses: [String]) -> UIImage? {
        for pose in poses {
            let key = "\(character.rawValue)-\(pose)"
            if let img = cache[key] { return img }
            if let url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "Mascots"),
               let img = UIImage(contentsOfFile: url.path) {
                cache[key] = img
                return img
            }
        }
        return nil
    }
}

/// A short horizontal shake (three swings).
private struct PhoneShake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(animatableData * .pi * 6), y: 0))
    }
}
