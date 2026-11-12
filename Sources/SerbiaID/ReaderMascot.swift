import SwiftUI

/// What the card reader "feels". Drives the little face in the sidebar and in the empty state.
enum ReaderMood: Equatable {
    case noReader    // nothing plugged in: grey, sleepy, sad
    case waiting     // reader connected, no card: looks up at the slot
    case ready       // card inserted: happy
    case busy        // reading: eyes scan left and right
    case error       // the last operation failed: worried
}

/// The card reader as a small character: a rounded body with a card slot on top, two eyes and a mouth.
/// The card slides into it when inserted.
///
/// Cheap by design: plain shapes, state-driven implicit animations, and one blink every few seconds.
/// Nothing animates while the window is inactive or when the system "Reduce motion" setting is on.
struct ReaderMascot: View {
    let mood: ReaderMood
    let card: Bool
    var size: CGFloat = 40

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var blink = false
    @State private var scan = false
    @State private var bounce = false
    @State private var shakes: CGFloat = 0
    @State private var wave: Double = 0

    private var tint: Color {
        switch mood {
        case .noReader: return Color.secondary
        case .waiting, .busy: return brandTint
        case .ready: return Color.green
        case .error: return Color.red
        }
    }

    /// -1 = frown ... +1 = big smile
    private var smile: CGFloat {
        switch mood {
        case .noReader: return -0.8
        case .waiting: return 0.25
        case .ready: return 1
        case .busy: return 0.1
        case .error: return -0.55
        }
    }

    private var eyeOpen: CGFloat { (mood == .noReader ? 0.5 : 1) * (blink ? 0.12 : 1) }

    private var gaze: CGSize {
        switch mood {
        case .noReader: return CGSize(width: 0, height: 2.5)      // looks down
        case .waiting: return CGSize(width: 0, height: -2.5)      // looks up at the slot
        case .busy: return CGSize(width: scan ? 3 : -3, height: 1)
        case .ready, .error: return .zero
        }
    }

    /// Cartoon eye: white with an outline and a pupil that follows the gaze; the lid squeezes it when blinking.
    private func eye(_ x: CGFloat, _ side: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(Color.white)
            Ellipse().strokeBorder(ink, lineWidth: 2)
            Circle().fill(Color(white: 0.12)).frame(width: 6.4, height: 6.4)
                .offset(x: -side * 1.2 + gaze.width * 0.8, y: 1 + gaze.height * 0.8)
        }
        .frame(width: 12.5, height: 15)
        .scaleEffect(CGSize(width: 1, height: eyeOpen), anchor: .center)
        .position(x: x, y: 59)
    }

    private func hand(_ x: CGFloat, _ y: CGFloat) -> some View {
        let inner: CGFloat = x < 50 ? 16 : 84
        return ZStack {
            Path { p in p.move(to: CGPoint(x: inner, y: 66)); p.addLine(to: CGPoint(x: x, y: y)) }
                .stroke(ink, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            Circle().fill(Color.white).overlay(Circle().strokeBorder(ink, lineWidth: 2.4))
                .frame(width: 10, height: 10).position(x: x, y: y)
        }
    }

    private var ink: Color { Color.primary.opacity(0.85) }
    private var animates: Bool { !reduceMotion && activeState != .inactive }

    var body: some View {
        ZStack {
            // the card, behind the body, so its lower part disappears into the slot
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.28), lineWidth: 2))
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.89, green: 0.70, blue: 0.25))
                        .frame(width: 12, height: 9).padding(6)
                }
                .frame(width: 44, height: 40)
                .position(x: 50, y: card ? 28 : 12)
                .opacity(card ? 1 : 0)

            // body: opaque base + a touch of the state colour
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint, lineWidth: 4))
                .frame(width: 68, height: 60)
                .position(x: 50, y: 62)
            Capsule().fill(tint.opacity(0.55)).frame(width: 50, height: 4).position(x: 50, y: 39)

            // little gloved hands; the left one waves when a card goes in
            hand(8.5, 64).rotationEffect(.degrees(wave), anchor: UnitPoint(x: 0.16, y: 0.67))
            hand(91.5, 64)

            // face
            eye(37.5, 1); eye(62.5, -1)
            Circle().fill(Color.pink.opacity(0.4)).frame(width: 12, height: 12).position(x: 29, y: 71).opacity(mood == .ready ? 1 : 0)
            Circle().fill(Color.pink.opacity(0.4)).frame(width: 12, height: 12).position(x: 71, y: 71).opacity(mood == .ready ? 1 : 0)
            MascotMouth(curve: smile).stroke(ink, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
        .frame(width: 100, height: 100)
        .scaleEffect(size / 100 * (bounce ? 1.09 : 1))
        .frame(width: size, height: size)
        .modifier(MascotShake(animatableData: shakes))
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.72), value: mood)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75), value: card)
        .accessibilityHidden(true)
        .onAppear { react(to: mood) }
        .onChange(of: mood) { react(to: $0) }
        .task(id: animates) {
            // one blink every few seconds; stops with the view, the window focus or Reduce Motion
            guard animates else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 3_200_000_000...6_500_000_000))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.09)) { blink = true }
                try? await Task.sleep(nanoseconds: 130_000_000)
                withAnimation(.easeInOut(duration: 0.12)) { blink = false }
            }
        }
    }

    private func react(to mood: ReaderMood) {
        guard !reduceMotion else { scan = false; return }
        if mood == .busy {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { scan = true }
        } else if scan {
            withAnimation(.easeOut(duration: 0.2)) { scan = false }
        }
        if mood == .ready {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { bounce = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { bounce = false }
            }
        }
        if mood == .ready {
            Task { @MainActor in
                for a in [-18.0, 6, -18, 6, 0] {
                    withAnimation(.easeInOut(duration: 0.16)) { wave = a }
                    try? await Task.sleep(nanoseconds: 160_000_000)
                }
            }
        }
        if mood == .error { withAnimation(.linear(duration: 0.45)) { shakes += 1 } }
    }
}

/// Mouth: a curve whose depth animates between a frown (-1) and a smile (+1).
private struct MascotMouth: Shape {
    var curve: CGFloat
    var animatableData: CGFloat {
        get { curve }
        set { curve = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 41, y: 77))
        p.addQuadCurve(to: CGPoint(x: 59, y: 77), control: CGPoint(x: 50, y: 77 + 9 * curve))
        return p
    }
}

/// A short horizontal shake (three swings), used once when something fails.
struct MascotShake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 4 * sin(animatableData * .pi * 6), y: 0))
    }
}
