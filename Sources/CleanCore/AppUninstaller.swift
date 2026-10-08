import AppKit
import Foundation

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let version: String?

    public var isRunning: Bool {
        guard let bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

public struct AppUninstaller: Sendable {
    public let home: URL
    public let appDirs: [URL]

    public init(home: URL = Paths.home, appDirs: [URL]? = nil) {
        self.home = home
        self.appDirs = appDirs ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    static let leftoverDirs = [
        "Application Support", "Caches", "Preferences", "Containers", "Group Containers",
        "Saved Application State", "HTTPStorages", "WebKit", "Logs", "LaunchAgents",
        "Application Scripts", "Cookies",
    ]

    public func listApps() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for dir in appDirs {
            for child in FileSizer.children(of: dir) {
                if child.pathExtension == "app" {
                    if let a = Self.app(at: child) { apps.append(a) }
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // One level of nesting, e.g. /Applications/Utilities or vendor folders.
                    for sub in FileSizer.children(of: child) where sub.pathExtension == "app" {
                        if let a = Self.app(at: sub) { apps.append(a) }
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func app(at url: URL) -> InstalledApp? {
        let resolved = url.resolvingSymlinksInPath()
        if resolved.path.hasPrefix("/System/") { return nil }
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        let bundleID = info?["CFBundleIdentifier"] as? String
        // Never offer to remove Apple's own apps.
        if bundleID?.hasPrefix("com.apple.") == true { return nil }
        let name = (info?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(url: url, name: name, bundleID: bundleID,
                            version: info?["CFBundleShortVersionString"] as? String)
    }

    public func findApp(named query: String) -> InstalledApp? {
        let q = query.lowercased().replacingOccurrences(of: ".app", with: "")
        let apps = listApps()
        return apps.first { $0.name.lowercased() == q || $0.url.deletingPathExtension().lastPathComponent.lowercased() == q }
            ?? apps.first { $0.bundleID?.lowercased() == q }
    }

    /// Files under ~/Library belonging to the app, matched by bundle ID or exact app name.
    public func leftovers(for app: InstalledApp) -> [URL] {
        let library = home.appendingPathComponent("Library")
        let bid = app.bundleID?.lowercased()
        let names = Set([app.name.lowercased(), app.url.deletingPathExtension().lastPathComponent.lowercased()])
        var out: [URL] = []
        for dir in Self.leftoverDirs {
            for child in FileSizer.children(of: library.appendingPathComponent(dir)) {
                let n = child.lastPathComponent.lowercased()
                let stem = (n as NSString).deletingPathExtension
                var match = names.contains(n) || names.contains(stem)
                if let bid, bid.split(separator: ".").count >= 3 || bid.count >= 10 {
                    match = match || n.contains(bid)
                }
                if match { out.append(child) }
            }
        }
        return out
    }

    /// The app bundle plus leftovers, sized.
    public func plan(for app: InstalledApp) async -> [ScanItem] {
        let urls = [app.url] + leftovers(for: app)
        let sizes = await FileSizer.sizes(of: urls)
        return urls.map { u in
            ScanItem(url: u, size: sizes[u] ?? 0, category: u == app.url ? "app" : "leftover", modified: FileSizer.modified(u))
        }
    }

    public func uninstall(_ items: [ScanItem], dryRun: Bool = false) -> TrashReport {
        Trash.move(items, dryRun: dryRun)
    }
}
