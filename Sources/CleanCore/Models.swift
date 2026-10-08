import Foundation

public struct ScanItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public let category: String
    public let modified: Date?
    /// Whether the item should be pre-selected for cleaning.
    public let selectedByDefault: Bool

    public init(url: URL, size: Int64, category: String, modified: Date? = nil, selectedByDefault: Bool = true) {
        self.url = url
        self.size = size
        self.category = category
        self.modified = modified
        self.selectedByDefault = selectedByDefault
    }

    public var name: String { url.lastPathComponent }
}

public extension Sequence where Element == ScanItem {
    var totalSize: Int64 { reduce(0) { $0 + $1.size } }
}

public enum Format {
    public static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    public static func date(_ d: Date?) -> String {
        guard let d else { return "-" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    /// Parses sizes like "500M", "1.5G", "100k", "2048".
    public static func parseSize(_ s: String) -> Int64? {
        let t = s.trimmingCharacters(in: .whitespaces).uppercased()
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3),
                                         ("T", 1e12), ("G", 1e9), ("M", 1e6), ("K", 1e3), ("B", 1)]
        for (suffix, mult) in units where t.hasSuffix(suffix) {
            guard let v = Double(t.dropLast(suffix.count)) else { return nil }
            return Int64(v * mult)
        }
        return Int64(t)
    }
}

public enum Paths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var library: URL { home.appendingPathComponent("Library") }

    /// Refuses anything that is not inside the user's home directory or /Applications.
    public static func isSafeToTrash(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        let homePath = home.standardizedFileURL.resolvingSymlinksInPath().path
        if p == homePath { return false }
        let protectedInHome = ["Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Applications", ".Trash"]
            .map { homePath + "/" + $0 }
        if protectedInHome.contains(p) { return false }
        if p.hasPrefix(homePath + "/") { return true }
        if p.hasPrefix("/Applications/") && p.hasSuffix(".app") { return true }
        return false
    }
}
