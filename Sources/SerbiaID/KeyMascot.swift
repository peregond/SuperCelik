import SwiftUI

/// The token's key as a little cartoon character (same moods as the reader): a gold key with a big face on its bow,
/// white-gloved hands and white shoes, in the spirit of old rubber-hose cartoons. It waves when a card is inserted,
/// scans with its eyes while reading, droops without a reader.
///
/// Cheap by design: plain shapes, state-driven animations and one blink every few seconds;
/// nothing moves while the window is inactive or when Reduce Motion is on.
struct KeyMascot: View {
    let mood: ReaderMood
    var size: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var blink = false
    @State private var scan = false
    @State private var bounce = false
    @State private var shakes: CGFloat = 0
    @State private var wave: Double = 0

    private var ink: Color { Color.primary.opacity(0.85) }
    private var animates: Bool { !reduceMotion && activeState != .inactive }
    private var bowColor: Color { mood == .noReader ? Color(white: 0.80) : Color(red: 0.95, green: 0.79, blue: 0.30) }
    private var shaftColor: Color { mood == .noReader ? Color(white: 0.70) : Color(red: 0.91, green: 0.73, blue: 0.24) }

    /// -1 = frown ... +1 = big smile
    private var smile: CGFloat {
        switch mood {
        case .noReader: return -0.8
        case .waiting: return 0.2
        case .ready: return 1
        case .busy: return 0.15
        case .error: return -0.6
        }
    }
    private var eyeOpen: CGFloat { (mood == .noReader ? 0.55 : 1) * (blink ? 0.1 : 1) }
    private var gaze: CGSize {
        switch mood {
        case .noReader: return CGSize(width: 0, height: 3)
        case .waiting: return CGSize(width: 0, height: -2)
        case .busy: return CGSize(width: scan ? 3 : -3, height: 0.5)
        case .ready, .error: return .zero
        }
    }
    /// brows: inner ends up when worried or sad
    private var browTilt: Double { mood == .noReader || mood == .error ? 14 : 0 }
    private var browLift: CGFloat { mood == .ready ? -2.5 : 0 }
    /// the left arm: raised when happy, half raised when waiting, hanging when sad
    private var armAngle: Double {
        switch mood {
        case .ready: return 0
        case .waiting, .busy: return -32
        case .noReader, .error: return -78
        }
    }

    private func stroked(_ path: Path, fill: Color? = nil, width: CGFloat = 3.2) -> some View {
        ZStack {
            if let fill { path.fill(fill) }
            path.stroke(ink, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }

    private func glove(_ x: CGFloat, _ y: CGFloat) -> some View {
        Circle().fill(Color.white)
            .overlay(Circle().strokeBorder(ink, lineWidth: 3.2))
            .frame(width: 12.4, height: 12.4).position(x: x, y: y)
    }

    private func shoe(_ x: CGFloat) -> some View {
        Ellipse().fill(Color.white)
            .overlay(Ellipse().strokeBorder(ink, lineWidth: 3.2))
            .frame(width: 15, height: 7.2).position(x: x, y: 93.5)
    }

    private func eye(_ x: CGFloat, _ side: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(Color.white)
            Ellipse().strokeBorder(ink, lineWidth: 2.4)
            ZStack {
                Circle().fill(Color(white: 0.12)).frame(width: 7.2, height: 7.2)
                Circle().fill(Color.white).frame(width: 2.2, height: 2.2).offset(x: 1.1, y: -1.2)
            }
            .offset(x: -side * 1.5 + gaze.width, y: 2 + gaze.height)
        }
        .frame(width: 14, height: 18)
        .scaleEffect(CGSize(width: 1, height: eyeOpen), anchor: .center)
        .position(x: x, y: 29)
    }

    var body: some View {
        ZStack {
            // legs and shoes
            stroked(Path { p in
                p.move(to: CGPoint(x: 46, y: 82)); p.addQuadCurve(to: CGPoint(x: 43, y: 91), control: CGPoint(x: 44, y: 88))
                p.move(to: CGPoint(x: 54, y: 82)); p.addQuadCurve(to: CGPoint(x: 57, y: 91), control: CGPoint(x: 56, y: 88))
            })
            shoe(39.5); shoe(60.5)

            // right arm (always relaxed)
            stroked(Path { p in
                p.move(to: CGPoint(x: 56, y: 64)); p.addQuadCurve(to: CGPoint(x: 78, y: 72), control: CGPoint(x: 70, y: 66))
            })
            glove(80, 73.5)

            // the key's teeth and shaft
            stroked(Path { p in
                p.move(to: CGPoint(x: 44, y: 66)); p.addLine(to: CGPoint(x: 33, y: 66)); p.addLine(to: CGPoint(x: 33, y: 71)); p.addLine(to: CGPoint(x: 44, y: 71))
                p.move(to: CGPoint(x: 44, y: 75)); p.addLine(to: CGPoint(x: 36, y: 75)); p.addLine(to: CGPoint(x: 36, y: 80)); p.addLine(to: CGPoint(x: 44, y: 80))
            }, fill: shaftColor)
            stroked(Path(CGRect(x: 44, y: 50, width: 12, height: 32)), fill: shaftColor)

            // bow
            Circle().fill(bowColor).frame(width: 50, height: 50).position(x: 50, y: 31)
            Circle().strokeBorder(ink, lineWidth: 3.2).frame(width: 50, height: 50).position(x: 50, y: 31)
            Path { p in p.move(to: CGPoint(x: 33, y: 18)); p.addQuadCurve(to: CGPoint(x: 46, y: 10), control: CGPoint(x: 38, y: 11)) }
                .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // left arm with the glove: raised, waves, hangs down
            ZStack {
                stroked(Path { p in
                    p.move(to: CGPoint(x: 44, y: 63)); p.addQuadCurve(to: CGPoint(x: 24, y: 50), control: CGPoint(x: 30, y: 62))
                })
                glove(22, 46)
            }
            .rotationEffect(.degrees(armAngle + wave), anchor: UnitPoint(x: 0.44, y: 0.63))

            // face
            eye(40, 1); eye(60, -1)
            Path { p in p.move(to: CGPoint(x: 33, y: 17)); p.addQuadCurve(to: CGPoint(x: 46, y: 17), control: CGPoint(x: 40, y: 13)) }
                .stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-browTilt), anchor: UnitPoint(x: 0.395, y: 0.16)).offset(y: browLift)
            Path { p in p.move(to: CGPoint(x: 54, y: 17)); p.addQuadCurve(to: CGPoint(x: 67, y: 17), control: CGPoint(x: 60, y: 13)) }
                .stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(browTilt), anchor: UnitPoint(x: 0.605, y: 0.16)).offset(y: browLift)
            Circle().fill(Color.pink.opacity(0.45)).frame(width: 9, height: 9).position(x: 31, y: 42).opacity(mood == .ready ? 1 : 0.35)
            Circle().fill(Color.pink.opacity(0.45)).frame(width: 9, height: 9).position(x: 69, y: 42).opacity(mood == .ready ? 1 : 0.35)
            KeyMouth(curve: smile, closed: true).fill(Color(red: 0.48, green: 0.13, blue: 0.19))
                .opacity(Double(max(0, min(1, (smile - 0.4) / 0.6))))
            KeyMouth(curve: smile, closed: false).stroke(ink, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 100, height: 100)
        .scaleEffect(size / 100 * (bounce ? 1.07 : 1), anchor: .bottom)
        .frame(width: size, height: size, alignment: .bottom)
        .modifier(MascotShake(animatableData: shakes))
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.72), value: mood)
        .accessibilityHidden(true)
        .onAppear { react(to: mood) }
        .onChange(of: mood) { react(to: $0) }
        .task(id: animates) {
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
            Task { @MainActor in   // a few waves, then rest
                for a in [14.0, -4, 14, -4, 8, 0] {
                    withAnimation(.easeInOut(duration: 0.2)) { wave = a }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
        if mood == .error { withAnimation(.linear(duration: 0.45)) { shakes += 1 } }
    }
}

/// The key's mouth: a curve between a frown (-1) and a big smile (+1); `closed` gives the filled (open) mouth.
private struct KeyMouth: Shape {
    var curve: CGFloat
    var closed: Bool
    var animatableData: CGFloat {
        get { curve }
        set { curve = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 42, y: 44))
        p.addQuadCurve(to: CGPoint(x: 58, y: 44), control: CGPoint(x: 50, y: 44 + 11 * curve))
        if closed { p.closeSubpath() }
        return p
    }
}
