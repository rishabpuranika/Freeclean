import Foundation

public enum JunkCategory: String, CaseIterable, Sendable, Identifiable {
    case userCaches = "caches"
    case logs
    case xcode
    case devCaches = "dev"
    case trash
    case oldDownloads = "downloads"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .userCaches: "User Caches"
        case .logs: "Logs"
        case .xcode: "Xcode & Simulators"
        case .devCaches: "Developer Caches"
        case .trash: "Trash"
        case .oldDownloads: "Old Downloads"
        }
    }

    public var detail: String {
        switch self {
        case .userCaches: "App caches in ~/Library/Caches. Apps rebuild them as needed."
        case .logs: "Diagnostic logs in ~/Library/Logs."
        case .xcode: "DerivedData, device support files, simulator caches. Archives are unselected by default."
        case .devCaches: "Homebrew, npm, pip, Yarn, Gradle, CocoaPods, Go build caches."
        case .trash: "Items already in your Trash. Emptying is permanent."
        case .oldDownloads: "Files in ~/Downloads untouched for 90+ days. Review before cleaning."
        }
    }

    /// Categories cleaned by default in a "Smart Scan".
    public var selectedByDefault: Bool {
        switch self {
        case .trash, .oldDownloads: false
        default: true
        }
    }
}

public struct JunkScanner: Sendable {
    public let home: URL
    public var downloadsAgeDays: Int = 90

    public init(home: URL = Paths.home) { self.home = home }

    private var library: URL { home.appendingPathComponent("Library") }
    private var caches: URL { library.appendingPathComponent("Caches") }

    /// Cache folders that belong to the developer category rather than generic user caches.
    private var devCacheNames: Set<String> { ["Homebrew", "pip", "Yarn", "CocoaPods", "go-build", "node-gyp"] }

    /// Candidate URLs per category, with whether each is selected by default.
    func candidates(for category: JunkCategory) -> [(URL, Bool)] {
        let fm = FileManager.default
        func exists(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) }
        switch category {
        case .userCaches:
            return FileSizer.children(of: caches)
                .filter { !devCacheNames.contains($0.lastPathComponent) }
                .map { ($0, true) }
        case .logs:
            return FileSizer.children(of: library.appendingPathComponent("Logs")).map { ($0, true) }
        case .xcode:
            let dev = library.appendingPathComponent("Developer")
            var out: [(URL, Bool)] = []
            out += FileSizer.children(of: dev.appendingPathComponent("Xcode/DerivedData")).map { ($0, true) }
            for sub in ["Xcode/iOS DeviceSupport", "Xcode/watchOS DeviceSupport", "Xcode/tvOS DeviceSupport", "Xcode/visionOS DeviceSupport"] {
                out += FileSizer.children(of: dev.appendingPathComponent(sub)).map { ($0, true) }
            }
            let simCaches = dev.appendingPathComponent("CoreSimulator/Caches")
            if exists(simCaches) { out.append((simCaches, true)) }
            out += FileSizer.children(of: dev.appendingPathComponent("Xcode/Archives")).map { ($0, false) }
            return out
        case .devCaches:
            let paths = devCacheNames.map { caches.appendingPathComponent($0) } + [
                home.appendingPathComponent(".npm/_cacache"),
                home.appendingPathComponent(".gradle/caches"),
                home.appendingPathComponent(".cache/pip"),
                home.appendingPathComponent(".cache/yarn"),
                library.appendingPathComponent("pnpm/store"),
            ]
            return paths.filter(exists).map { ($0, true) }
        case .trash:
            let t = home.appendingPathComponent(".Trash")
            return exists(t) ? [(t, true)] : []
        case .oldDownloads:
            let cutoff = Date().addingTimeInterval(-Double(downloadsAgeDays) * 86_400)
            return FileSizer.children(of: home.appendingPathComponent("Downloads"))
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .filter { (FileSizer.modified($0) ?? .distantFuture) < cutoff }
                .map { ($0, false) }
        }
    }

    public func scan(_ category: JunkCategory) async -> [ScanItem] {
        let cands = candidates(for: category)
        let sizes = await FileSizer.sizes(of: cands.map(\.0))
        return cands.compactMap { url, selected in
            let size = sizes[url] ?? 0
            guard size > 0 else { return nil }
            return ScanItem(url: url, size: size, category: category.rawValue,
                            modified: FileSizer.modified(url), selectedByDefault: selected)
        }
        .sorted { $0.size > $1.size }
    }

    public func scanAll(_ categories: [JunkCategory] = JunkCategory.allCases) async -> [JunkCategory: [ScanItem]] {
        var out: [JunkCategory: [ScanItem]] = [:]
        for c in categories { out[c] = await scan(c) }
        return out
    }

    /// Cleans items: Trash-category items are permanently emptied, everything else moves to the Trash.
    public func clean(_ items: [ScanItem], dryRun: Bool = false) -> TrashReport {
        let trashItems = items.filter { $0.category == JunkCategory.trash.rawValue }
        var report = Trash.move(items.filter { $0.category != JunkCategory.trash.rawValue }, dryRun: dryRun)
        if !trashItems.isEmpty {
            if dryRun {
                report.freed += trashItems.totalSize
                report.trashed += trashItems.map(\.url)
            } else {
                let r = Trash.empty()
                report.freed += r.freed
                report.trashed += r.trashed
                report.failed += r.failed
            }
        }
        return report
    }
}
