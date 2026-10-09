import CleanCore
import SwiftUI

extension Screen {
    var colors: [Color] {
        switch self {
        case .junk: [Color(red: 0.98, green: 0.36, blue: 0.62), Color(red: 0.55, green: 0.32, blue: 0.96)]
        case .large: [Color(red: 1.0, green: 0.62, blue: 0.2), Color(red: 0.96, green: 0.36, blue: 0.24)]
        case .uninstaller: [Color(red: 0.25, green: 0.7, blue: 1.0), Color(red: 0.2, green: 0.4, blue: 0.95)]
        case .disk: [Color(red: 0.24, green: 0.84, blue: 0.62), Color(red: 0.1, green: 0.6, blue: 0.7)]
        case .memory: [Color(red: 0.55, green: 0.5, blue: 1.0), Color(red: 0.36, green: 0.28, blue: 0.86)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var subtitle: String {
        switch self {
        case .junk: "Clear caches, logs and developer leftovers"
        case .large: "Find big files and things you no longer use"
        case .uninstaller: "Remove apps completely, leftovers included"
        case .disk: "See what's taking up your space"
        case .memory: "Memory use, heavy processes and startup items"
        }
    }
}

extension JunkCategory {
    var icon: String {
        switch self {
        case .userCaches: "archivebox.fill"
        case .logs: "doc.text.fill"
        case .xcode: "hammer.fill"
        case .devCaches: "shippingbox.fill"
        case .trash: "trash.fill"
        case .oldDownloads: "arrow.down.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .userCaches: .blue
        case .logs: .teal
        case .xcode: .indigo
        case .devCaches: .orange
        case .trash: .red
        case .oldDownloads: .green
        }
    }
}

/// System Settings–style rounded icon tile with a glossy top highlight.
struct IconTile: View {
    let symbol: String
    let gradient: LinearGradient
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(gradient)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.25), radius: size * 0.08, y: size * 0.04)
    }
}

extension IconTile {
    init(_ screen: Screen, size: CGFloat = 22) {
        self.init(symbol: screen.icon, gradient: screen.gradient, size: size)
    }

    init(_ category: JunkCategory, size: CGFloat = 22) {
        self.init(symbol: category.icon,
                  gradient: LinearGradient(colors: [category.color.opacity(0.8), category.color],
                                           startPoint: .top, endPoint: .bottom),
                  size: size)
    }
}

/// Large title area at the top of every screen.
struct PageHeader<Trailing: View>: View {
    let screen: Screen
    var title: String?
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            IconTile(screen, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? screen.rawValue).font(.system(size: 24, weight: .bold))
                Text(subtitle ?? screen.subtitle).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .appear()
    }
}

extension PageHeader where Trailing == EmptyView {
    init(screen: Screen, title: String? = nil, subtitle: String? = nil) {
        self.init(screen: screen, title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension View {
    /// Glass panel used for every card in the app.
    func card(padding: CGFloat = 16, tint: Color? = nil) -> some View {
        self.padding(padding).glass(cornerRadius: 18, tint: tint)
    }
}

/// Glowing gradient capsule with a glassy sheen, for primary actions.
struct GradientButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    var large = false
    var glow: Color = .white
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 30 : 20)
            .padding(.vertical, large ? 12 : 8)
            .background(gradient, in: Capsule())
            .overlay(
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center))
                    .padding(1.5)
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.8))
            .shadow(color: glow.opacity(isEnabled ? (hovering ? 0.55 : 0.3) : 0), radius: hovering ? 16 : 10, y: 4)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : hovering && isEnabled ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension GradientButtonStyle {
    init(screen: Screen, large: Bool = false) {
        self.init(gradient: screen.gradient, large: large, glow: screen.colors[1])
    }
}

/// The big animated orb button used on landing screens (inspired by CleanMyMac's scan button).
struct HeroButton: View {
    let screen: Screen
    let title: String
    var busy = false
    /// 0...1 when scanning with known progress.
    var progress: Double?
    let action: () -> Void
    @ViewState private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let breathe = reduceMotion ? 0 : sin(t * (busy ? 3 : 1.4))
                orb(t: t, breathe: breathe)
            }
            .frame(width: 260, height: 260)
            .contentShape(Circle().inset(by: 40))
        }
        .buttonStyle(OrbPressStyle())
        .disabled(busy)
        .onHover { h in withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { hovering = h } }
    }

    private func orb(t: Double, breathe: Double) -> some View {
        let spin = Angle.degrees(reduceMotion ? 0 : t * (busy ? 160 : 28))
        return ZStack {
            // Soft outer glow that breathes.
            Circle()
                .fill(RadialGradient(colors: [screen.colors[1].opacity(0.55), .clear], center: .center,
                                     startRadius: 60, endRadius: 130))
                .scaleEffect(1 + 0.05 * breathe + (hovering ? 0.06 : 0))

            // Rotating light ring.
            Circle()
                .strokeBorder(AngularGradient(colors: [screen.colors[0], .white.opacity(0.9), screen.colors[1],
                                                       screen.colors[0].opacity(0.1), screen.colors[0]],
                                              center: .center),
                              lineWidth: busy ? 4 : 2.5)
                .frame(width: 196, height: 196)
                .rotationEffect(spin)
                .blur(radius: 0.6)
                .opacity(0.9)

            if busy {
                if let progress, progress > 0 {
                    Circle().trim(from: 0, to: progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 214, height: 214)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .white.opacity(0.7), radius: 6)
                        .animation(.smooth, value: progress)
                }
                // Orbiting sparks.
                ForEach(0..<3) { i in
                    Circle().fill(.white).frame(width: 6, height: 6)
                        .shadow(color: .white, radius: 4)
                        .offset(y: -107)
                        .rotationEffect(.degrees(t * (120 + Double(i) * 40) + Double(i) * 120))
                }
            }

            // Glass orb.
            ZStack {
                Circle().fill(screen.gradient)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.5), .clear], center: .init(x: 0.35, y: 0.2),
                                             startRadius: 2, endRadius: 90))
                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top,
                                              endPoint: .bottom))
                    .frame(width: 110, height: 52)
                    .offset(y: -44)
                    .blur(radius: 2)
                Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1)
                VStack(spacing: 6) {
                    Image(systemName: screen.icon)
                        .font(.system(size: 44, weight: .semibold))
                        .symbolEffect(.pulse, isActive: busy)
                        .symbolEffect(.bounce, value: hovering)
                    Text(busy ? "Scanning" : title).font(.title3.weight(.semibold))
                        .contentTransition(.opacity)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .frame(width: 168, height: 168)
            .shadow(color: screen.colors[1].opacity(0.6), radius: hovering ? 30 : 20, y: 10)
            .scaleEffect(1 + 0.015 * breathe + (hovering ? 0.04 : 0))
        }
    }
}

private struct OrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SuccessView: View {
    let screen: Screen
    let report: TrashReport
    let doneTitle: String
    let done: () -> Void
    @ViewState private var drawn = false

    var body: some View {
        ZStack {
            Burst(colors: screen.colors + [.white, .green])
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [.green.opacity(0.5), .clear], center: .center,
                                                 startRadius: 40, endRadius: 110))
                        .frame(width: 220, height: 220)
                    Circle().fill(LinearGradient(colors: [Color(red: 0.3, green: 0.9, blue: 0.55),
                                                          Color(red: 0.1, green: 0.65, blue: 0.45)],
                                                 startPoint: .top, endPoint: .bottom))
                        .frame(width: 128, height: 128)
                        .overlay(Circle().strokeBorder(.white.opacity(0.4)))
                        .shadow(color: .green.opacity(0.6), radius: 24, y: 8)
                    Circle().trim(from: 0, to: drawn ? 1 : 0)
                        .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees(-90))
                    CheckmarkShape().trim(from: 0, to: drawn ? 1 : 0)
                        .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                        .frame(width: 54, height: 42)
                }
                .scaleEffect(drawn ? 1 : 0.6)
                CountUpBytes(target: report.freed)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .appear(delay: 0.3)
                Text("cleaned up from \(report.trashed.count) item\(report.trashed.count == 1 ? "" : "s")")
                    .font(.title3).foregroundStyle(.white.opacity(0.7))
                    .appear(delay: 0.4)
                if !report.failed.isEmpty {
                    Label("\(report.failed.count) item(s) couldn't be removed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(report.failed.map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n"))
                }
                Text("Removed items are in the Trash if you need them back.")
                    .font(.callout).foregroundStyle(.white.opacity(0.55))
                    .appear(delay: 0.5)
                Button(doneTitle, action: done).buttonStyle(GradientButtonStyle(screen: screen, large: true))
                    .padding(.top, 6)
                    .appear(delay: 0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.1)) { drawn = true } }
    }
}

struct CheckmarkShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.05))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}
