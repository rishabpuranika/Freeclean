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
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
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

    var body: some View {
        NavigationSplitView {
            List(selection: $screen) {
                Section("Cleanup") {
                    ForEach([Screen.junk, .large, .uninstaller]) { row($0) }
                }
                Section("Performance") {
                    ForEach([Screen.disk, .memory]) { row($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) { SidebarDiskGauge().padding(12) }
        } detail: {
            Group {
                switch screen ?? .junk {
                case .junk: JunkView(model: junk)
                case .large: LargeFilesView(model: large)
                case .uninstaller: UninstallerView(model: apps)
                case .disk: DiskView()
                case .memory: MemoryStartupView()
                }
            }
            .navigationTitle("")
        }
    }

    private func row(_ s: Screen) -> some View {
        Label { Text(s.rawValue) } icon: { IconTile(s) }
            .padding(.vertical, 2)
            .tag(s)
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
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onReceive(timer) { _ in volume = DiskUsage.volume() }
    }
}
