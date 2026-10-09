import CleanCore
import SwiftUI

// MARK: - Glass

/// Liquid Glass is composited by the window server, so offscreen snapshots can't capture it.
/// Snapshot mode flips this to draw the material fallback instead.
nonisolated(unsafe) var useLiquidGlass = ProcessInfo.processInfo.environment["FREECLEAN_SNAPSHOT"] == nil

extension View {
    /// Liquid Glass on macOS 26+, frosted material before that.
    @ViewBuilder
    func glass(cornerRadius: CGFloat = 18, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *), useLiquidGlass {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background((tint ?? .clear).opacity(0.25), in: shape)
                .background(Color.white.opacity(0.07), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14)))
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *), useLiquidGlass {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: Capsule())
        } else {
            background((tint ?? .clear).opacity(0.3), in: Capsule())
                .background(Color.white.opacity(0.1), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.16)))
        }
    }
}

// MARK: - Live background

extension Screen {
    /// Deep, saturated colors for the animated backdrop (always rendered dark).
    var backdrop: [Color] {
        switch self {
        case .junk: [.init(red: 0.33, green: 0.09, blue: 0.42), .init(red: 0.62, green: 0.13, blue: 0.45),
                     .init(red: 0.12, green: 0.16, blue: 0.48), .init(red: 0.05, green: 0.33, blue: 0.45)]
        case .large: [.init(red: 0.45, green: 0.16, blue: 0.06), .init(red: 0.62, green: 0.3, blue: 0.08),
                      .init(red: 0.34, green: 0.07, blue: 0.2), .init(red: 0.2, green: 0.1, blue: 0.3)]
        case .uninstaller: [.init(red: 0.05, green: 0.2, blue: 0.5), .init(red: 0.1, green: 0.42, blue: 0.62),
                            .init(red: 0.15, green: 0.1, blue: 0.45), .init(red: 0.03, green: 0.3, blue: 0.38)]
        case .disk: [.init(red: 0.03, green: 0.32, blue: 0.3), .init(red: 0.08, green: 0.48, blue: 0.36),
                     .init(red: 0.05, green: 0.18, blue: 0.4), .init(red: 0.12, green: 0.35, blue: 0.15)]
        case .memory: [.init(red: 0.2, green: 0.12, blue: 0.5), .init(red: 0.38, green: 0.18, blue: 0.62),
                       .init(red: 0.08, green: 0.12, blue: 0.4), .init(red: 0.45, green: 0.12, blue: 0.4)]
        }
    }
}

/// Slowly drifting mesh gradient with floating sparkles, like CleanMyMac's live backdrop.
struct LiveBackground: View {
    let screen: Screen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.04, blue: 0.1)
            ForEach([screen]) { s in
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
                    let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
                    mesh(s.backdrop, t: t)
                }
                .transition(.opacity)
            }
            ParticleField()
                .blendMode(.plusLighter)
                .opacity(0.55)
            // Vignette keeps text readable at the edges.
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 200, endRadius: 900)
        }
        .animation(.easeInOut(duration: 0.9), value: screen)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func mesh(_ c: [Color], t: Double) -> some View {
        if #available(macOS 15, *) {
            let w = { (phase: Double, amp: Float) in Float(sin(t * 0.25 + phase)) * amp }
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + w(0, 0.12), 0], [1, 0],
                [0, 0.5 + w(1.3, 0.14)], [0.5 + w(2.1, 0.16), 0.5 + w(0.7, 0.16)], [1, 0.5 + w(2.9, 0.14)],
                [0, 1], [0.5 + w(3.7, 0.12), 1], [1, 1],
            ], colors: [
                c[0], c[2], c[1],
                c[3], c[0].mix(with: c[1], by: 0.5 + 0.5 * sin(t * 0.2)), c[2],
                c[1], c[3], c[0],
            ])
            .saturation(1.1)
        } else {
            ZStack {
                RadialGradient(colors: [c[1], .clear], center: .init(x: 0.25 + 0.1 * sin(t * 0.2), y: 0.3),
                               startRadius: 0, endRadius: 600)
                RadialGradient(colors: [c[2], .clear], center: .init(x: 0.8, y: 0.75 + 0.1 * cos(t * 0.2)),
                               startRadius: 0, endRadius: 600)
            }
            .background(c[0])
        }
    }
}

private extension Color {
    func mix(with other: Color, by f: Double) -> Color {
        if #available(macOS 15, *) { return mix(with: other, by: f, in: .perceptual) }
        return self
    }
}

/// Tiny glowing dust drifting upward.
struct ParticleField: View {
    var count = 46
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let seed = Double(i) * 12.9898
                    let rx = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1).magnitude
                    let speed = 6 + rx * 14
                    let ry = (cos(seed * 1.7) * 24634.6345).truncatingRemainder(dividingBy: 1).magnitude
                    let y = (ry * size.height - t * speed).truncatingRemainder(dividingBy: size.height)
                    let yy = y < 0 ? y + size.height : y
                    let x = rx * size.width + sin(t * 0.4 + seed) * 18
                    let r = 0.8 + rx * 1.8
                    let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * (1 + rx * 2) + seed))
                    g.opacity = twinkle
                    g.fill(Path(ellipseIn: CGRect(x: x, y: yy, width: r * 2, height: r * 2)), with: .color(.white))
                }
            }
        }
    }
}

// MARK: - Motion helpers

/// Text that counts up to a byte size.
struct CountingBytes: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Int64(value).bytes).monospacedDigit()
    }
}

/// Animates its value from 0 the first time it appears, then to any new value.
struct CountUpBytes: View {
    let target: Int64
    @ViewState private var shown: Double = 0

    var body: some View {
        CountingBytes(value: shown)
            .onAppear { withAnimation(.easeOut(duration: 1.1)) { shown = Double(target) } }
            .onChange(of: target) { _, new in withAnimation(.easeOut(duration: 0.6)) { shown = Double(new) } }
    }
}

/// Fades and springs a view in, optionally delayed, for staggered entrances.
struct AppearEffect: ViewModifier {
    var delay: Double
    @ViewState private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .scaleEffect(shown || reduceMotion ? 1 : 0.96)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func appear(delay: Double = 0) -> some View { modifier(AppearEffect(delay: delay)) }
}

/// One-shot burst of colored particles, used when cleaning finishes.
struct Burst: View {
    let colors: [Color]
    @ViewState private var start = Date()

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSince(start)
                guard t < 1.8 else { return }
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<36 {
                    let a = Double(i) / 36 * .pi * 2 + Double(i % 3) * 0.2
                    let speed = 120 + Double((i * 37) % 90)
                    let d = speed * (1 - pow(1 - min(t / 1.2, 1), 3))
                    let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d + t * t * 30)
                    let r = 3.5 * (1 - t / 1.8)
                    g.opacity = max(0, 1 - t / 1.8)
                    g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
