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

/// System Settings–style rounded icon tile.
struct IconTile: View {
    let symbol: String
    let gradient: LinearGradient
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(gradient)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: size * 0.06, y: size * 0.03)
    }
}

extension IconTile {
    init(_ screen: Screen, size: CGFloat = 22) {
        self.init(symbol: screen.icon, gradient: screen.gradient, size: size)
    }

    init(_ category: JunkCategory, size: CGFloat = 22) {
        self.init(symbol: category.icon,
                  gradient: LinearGradient(colors: [category.color.opacity(0.85), category.color],
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
            IconTile(screen, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? screen.rawValue).font(.title2.weight(.bold))
                Text(subtitle ?? screen.subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(screen: Screen, title: String? = nil, subtitle: String? = nil) {
        self.init(screen: screen, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Rounded card surface that adapts to light and dark mode.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

/// Capsule button filled with a screen's gradient.
struct GradientButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 28 : 18)
            .padding(.vertical, large ? 11 : 7)
            .background(gradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            .shadow(color: .black.opacity(isEnabled ? 0.18 : 0), radius: 6, y: 3)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The big round scan button used on landing screens.
struct HeroButton: View {
    let screen: Screen
    let title: String
    var busy = false
    let action: () -> Void
    @ViewState private var hovering = false
    @ViewState private var spin = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(screen.gradient.opacity(0.18)).frame(width: 210, height: 210)
                    .scaleEffect(hovering ? 1.04 : 1)
                if busy {
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(screen.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 196, height: 196)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                        .onAppear { spin = true }
                }
                Circle().fill(screen.gradient).frame(width: 160, height: 160)
                    .shadow(color: screen.colors.last!.opacity(0.45), radius: hovering ? 22 : 14, y: 8)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                VStack(spacing: 6) {
                    Image(systemName: screen.icon).font(.system(size: 42, weight: .semibold))
                    Text(title).font(.title3.weight(.semibold))
                }
                .foregroundStyle(.white)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
    }
}

/// Soft colored glow behind landing screens.
struct GlowBackground: View {
    let screen: Screen

    var body: some View {
        // Radial gradients instead of blurred circles: soft edges and cheap to draw.
        ZStack {
            RadialGradient(colors: [screen.colors[0].opacity(0.22), .clear], center: .init(x: 0.3, y: 0.3),
                           startRadius: 0, endRadius: 420)
            RadialGradient(colors: [screen.colors[1].opacity(0.18), .clear], center: .init(x: 0.72, y: 0.75),
                           startRadius: 0, endRadius: 420)
        }
        .allowsHitTesting(false)
    }
}

struct SuccessView: View {
    let screen: Screen
    let report: TrashReport
    let doneTitle: String
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(.green.gradient).frame(width: 120, height: 120)
                    .shadow(color: .green.opacity(0.4), radius: 16, y: 6)
                Image(systemName: "checkmark").font(.system(size: 54, weight: .bold)).foregroundStyle(.white)
            }
            Text(report.freed.bytes).font(.system(size: 44, weight: .bold, design: .rounded))
            Text("cleaned up from \(report.trashed.count) item\(report.trashed.count == 1 ? "" : "s")")
                .font(.title3).foregroundStyle(.secondary)
            if !report.failed.isEmpty {
                Label("\(report.failed.count) item(s) couldn't be removed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(report.failed.map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n"))
            }
            Text("Removed items are in the Trash if you need them back.").font(.callout).foregroundStyle(.secondary)
            Button(doneTitle, action: done).buttonStyle(GradientButtonStyle(gradient: screen.gradient, large: true))
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
