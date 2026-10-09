import Combine
import AppKit
import CleanCore
import SwiftUI

@main
struct FreeCleanApp: App {
    init() {
        // Needed when launched as a bare SPM executable (swift run) so the window comes to front.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let dir = ProcessInfo.processInfo.environment["FREECLEAN_SNAPSHOT"] {
            Task { @MainActor in await Snapshotter.run(into: URL(fileURLWithPath: dir)) }
        }
    }

    var body: some Scene {
        WindowGroup("FreeClean") {
            ContentView()
                .frame(minWidth: 1000, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case junk = "Smart Scan"
    case large = "Large & Old Files"
    case uninstaller = "Uninstaller"
    case disk = "Disk Usage"
    case memory = "Memory & Startup"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .junk: "sparkles"
        case .large: "doc.on.doc.fill"
        case .uninstaller: "xmark.app.fill"
        case .disk: "internaldrive.fill"
        case .memory: "memorychip.fill"
        }
    }
}

struct ContentView: View {
    @ViewState var screen: Screen? = .junk
    @ViewState var junk = JunkModel()
    @ViewState var large = LargeFilesModel()
    @ViewState var apps = UninstallerModel()

    private var current: Screen { screen ?? .junk }

    var body: some View {
        // A custom sidebar instead of NavigationSplitView: the system split view paints opaque chrome
        // over parts of the window, which breaks up the live background. Here one backdrop fills the
        // whole window and the sidebar floats on it as glass, like CleanMyMac.
        HStack(spacing: 0) {
            Sidebar(selection: Binding(get: { current }, set: { screen = $0 }))
                .frame(width: 228)
            ZStack {
                switch current {
                case .junk: JunkView(model: junk)
                case .large: LargeFilesView(model: large)
                case .uninstaller: UninstallerView(model: apps)
                case .disk: DiskView()
                case .memory: MemoryStartupView()
                }
            }
            .id(current)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 14)).combined(with: .scale(scale: 0.985)),
                removal: .opacity
            ))
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 22)
            .clipped()
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: current)
        .background {
            // Raycast/Dock-style: the desktop shows through a real behind-window blur, washed with
            // the screen's drifting colors.
            ZStack {
                WindowVibrancy(material: .hudWindow)
                LiveBackground(screen: current, tint: 0.55)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .tint(current.colors[1])
    }
}

struct Sidebar: View {
    @Binding var selection: Screen
    @Namespace private var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Room for the traffic-light buttons, which sit inside the sidebar like in Finder or CleanMyMac.
            Color.clear.frame(height: 30)
            section("Cleanup", [.junk, .large, .uninstaller])
            section("Performance", [.disk, .memory])
            Spacer(minLength: 12)
            SidebarDiskGauge()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity)
        // Full-height column flush with the window edge: a slightly darker translucent strip with a
        // hairline, like Raycast's or Finder's sidebar.
        .background(.black.opacity(0.2))
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
    }

    private func section(_ title: String, _ screens: [Screen]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 2)
            ForEach(screens) { row($0) }
        }
    }

    private func row(_ s: Screen) -> some View {
        let selected = selection == s
        return Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { selection = s }
        } label: {
            HStack(spacing: 10) {
                IconTile(s, size: 26)
                Text(s.rawValue)
                    .font(.system(size: 13, weight: selected ? .bold : .semibold))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.92))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: s.colors.map { $0.opacity(0.35) }, startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.18)))
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle())
        .keyboardShortcut(KeyEquivalent(Character("\((Screen.allCases.firstIndex(of: s) ?? 0) + 1)")), modifiers: .command)
    }
}

private struct SidebarRowStyle: ButtonStyle {
    @ViewState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.12 : 0)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// Compact free-space indicator pinned to the bottom of the sidebar.
struct SidebarDiskGauge: View {
    @ViewState private var volume = DiskUsage.volume()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").foregroundStyle(.secondary)
                Text("Macintosh HD").font(.caption.weight(.semibold))
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                } label: {
                    Image(systemName: "lock.shield")
                }
                .buttonStyle(.borderless)
                .help("Grant Full Disk Access so FreeClean can see everything (e.g. the Trash)")
            }
            if let v = volume {
                let frac = Double(v.used) / Double(max(v.total, 1))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill((frac > 0.9 ? Color.red : frac > 0.75 ? .orange : .accentColor).gradient)
                            .frame(width: geo.size.width * frac)
                    }
                }
                .frame(height: 6)
                Text("\(v.availableImportant.bytes) available of \(v.total.bytes)")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.92))
                    .contentTransition(.numericText())
            }
        }
        .padding(12)
        .glass(.secondary, cornerRadius: 18)
        .onReceive(timer) { _ in volume = DiskUsage.volume() }
    }
}
