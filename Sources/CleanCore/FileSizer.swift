import Foundation

public enum FileSizer {
    static let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]

    /// Allocated on-disk size of a file or directory tree. Unreadable entries are skipped.
    public static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        guard let rv = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if rv.isSymbolicLink == true { return 0 }
        if rv.isDirectory != true {
            return Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return 0
        }
        var total: Int64 = 0
        for case let child as URL in e {
            guard let v = try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]),
                  v.isDirectory != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Sizes many URLs concurrently.
    public static func sizes(of urls: [URL]) async -> [URL: Int64] {
        await withTaskGroup(of: (URL, Int64).self) { group in
            for u in urls { group.addTask { (u, size(of: u)) } }
            var out: [URL: Int64] = [:]
            for await (u, s) in group { out[u] = s }
            return out
        }
    }

    public static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Immediate children of a directory, or [] if unreadable.
    public static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }
}
