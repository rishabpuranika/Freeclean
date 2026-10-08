import Foundation

public struct LargeFileScanner: Sendable {
    public var root: URL
    public var minSize: Int64
    /// If set, also include files at least `oldMinSize` big that haven't been touched for this many days.
    public var olderThanDays: Int?
    public var oldMinSize: Int64 = 10_000_000
    public var skipDirNames: Set<String> = [".git", "node_modules", ".Trash", ".build"]
    /// Skips ~/Library (caches etc. are handled by the junk scanner).
    public var skipLibrary = true
    public var includeHidden = false

    public init(root: URL = Paths.home, minSize: Int64 = 100_000_000, olderThanDays: Int? = 365) {
        self.root = root
        self.minSize = minSize
        self.olderThanDays = olderThanDays
    }

    public func scan(progress: (@Sendable (Int) -> Void)? = nil) -> [ScanItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey, .contentAccessDateKey, .contentModificationDateKey, .isPackageKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                     options: includeHidden ? [] : [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return [] }
        let libraryPath = Paths.library.path
        let cutoff = olderThanDays.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        var out: [ScanItem] = []
        var seen = 0
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true {
                if skipDirNames.contains(url.lastPathComponent) || (skipLibrary && url.path == libraryPath) {
                    e.skipDescendants()
                }
                continue
            }
            guard v.isRegularFile == true else { continue }
            seen += 1
            if seen % 2000 == 0 { progress?(seen) }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            let lastUsed = [v.contentAccessDate, v.contentModificationDate].compactMap { $0 }.max()
            let isLarge = size >= minSize
            let isOld = cutoff.map { c in size >= oldMinSize && (lastUsed ?? .distantFuture) < c } ?? false
            if isLarge || isOld {
                out.append(ScanItem(url: url, size: size, category: isLarge ? "large" : "old",
                                    modified: lastUsed, selectedByDefault: false))
            }
        }
        return out.sorted { $0.size > $1.size }
    }
}
