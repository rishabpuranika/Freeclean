import AppKit
import CleanCore
import SwiftUI

/// Developer aid: `FREECLEAN_SNAPSHOT=<dir> FreeClean` renders every screen (light + dark) to PNGs and quits.
/// Rendering happens offscreen, so it needs no Screen Recording permission.
@MainActor
enum Snapshotter {
    static func run(into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let env = ProcessInfo.processInfo.environment
        let only = env["FREECLEAN_SNAPSHOT_ONLY"]
        // e.g. FREECLEAN_SNAPSHOT_SIZE=1000x680 to check small windows.
        let dims = (env["FREECLEAN_SNAPSHOT_SIZE"] ?? "1120x740").split(separator: "x").compactMap { Double($0) }
        let size = dims.count == 2 ? CGSize(width: dims[0], height: dims[1]) : CGSize(width: 1120, height: 740)

        let junk = JunkModel()
        let large = LargeFilesModel()
        let apps = UninstallerModel()
        await junk.scan()
        junk.inspected = .userCaches
        large.minSizeMB = 500
        large.includeHidden = true
        await large.scan()
        await apps.load()
        await apps.select(apps.apps.first { $0.name == "Bruno" } ?? apps.apps.first)

        let landing = (JunkModel(), LargeFilesModel())
        var shots: [(String, Screen, JunkModel, LargeFilesModel)] = Screen.allCases.map { ($0.id, $0, junk, large) }
        shots.append(("Smart Scan landing", .junk, landing.0, landing.1))
        shots.append(("Large landing", .large, landing.0, landing.1))
        let scanning = JunkModel()
        shots.append(("Smart Scan scanning", .junk, scanning, landing.1))
        let done = JunkModel()
        var fake = TrashReport()
        fake.freed = 2_480_000_000
        fake.trashed = Array(repeating: Paths.home, count: 42)
        done.report = fake
        done.phase = .done
        shots.append(("Smart Scan done", .junk, done, landing.1))

        for (name, screen, j, l) in shots where only.map({ name.localizedCaseInsensitiveContains($0) }) ?? true {
            for dark in [false, true] {
                let view = ContentView(screen: screen, junk: j, large: l, apps: apps)
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                                      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                // Match the real window (.hiddenTitleBar): transparent title bar, content underneath.
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = NSHostingView(rootView: view)
                window.orderFrontRegardless()
                if j === scanning { Task { await scanning.scan() } }
                let wait: Double = j === scanning ? 1.2 : j === done ? 1.6 : screen == .memory ? 7 : screen == .disk ? 25 : 3
                try? await Task.sleep(for: .seconds(wait))
                guard let target = window.contentView?.superview ?? window.contentView else { continue }
                if let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) {
                    target.cacheDisplay(in: target.bounds, to: rep)
                    let file = dir.appendingPathComponent("\(name.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "&", with: "and"))-\(dark ? "dark" : "light").png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: file)
                    print("wrote \(file.path)")
                }
                window.close()
            }
        }
        exit(0)
    }
}
