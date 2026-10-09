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
