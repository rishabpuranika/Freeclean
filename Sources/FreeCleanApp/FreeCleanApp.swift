import AppKit
import SwiftUI

@main
struct FreeCleanApp: App {
    init() {
        // Needed when launched as a bare SPM executable (swift run) so the window comes to front.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("FreeClean") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
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
        case .large: "doc.on.doc"
        case .uninstaller: "trash.square"
        case .disk: "internaldrive"
        case .memory: "memorychip"
        }
    }
}

struct ContentView: View {
    @ViewState private var screen: Screen? = .junk
    @ViewState private var junk = JunkModel()
    @ViewState private var large = LargeFilesModel()
    @ViewState private var apps = UninstallerModel()

    var body: some View {
        NavigationSplitView {
            List(Screen.allCases, selection: $screen) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { FullDiskAccessHint().padding(10) }
        } detail: {
            switch screen ?? .junk {
            case .junk: JunkView(model: junk)
            case .large: LargeFilesView(model: large)
            case .uninstaller: UninstallerView(model: apps)
            case .disk: DiskView()
            case .memory: MemoryStartupView()
            }
        }
    }
}

struct FullDiskAccessHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Some folders (like Trash) need Full Disk Access.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .controlSize(.small)
        }
    }
}
