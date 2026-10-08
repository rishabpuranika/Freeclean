import Foundation

public struct VolumeInfo: Sendable {
    public let total: Int64
    public let available: Int64
    public let availableImportant: Int64
    public var used: Int64 { total - available }
}

public enum DiskUsage {
    public static func volume(_ url: URL = URL(fileURLWithPath: "/")) -> VolumeInfo? {
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                                         .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity else { return nil }
        let avail = Int64(v.volumeAvailableCapacity ?? 0)
        return VolumeInfo(total: Int64(total), available: avail,
                          availableImportant: v.volumeAvailableCapacityForImportantUsage ?? avail)
    }

    /// Sizes of the immediate children of `root` (including hidden ones), largest first.
    public static func breakdown(of root: URL = Paths.home) async -> [ScanItem] {
        let kids = FileSizer.children(of: root)
        let sizes = await FileSizer.sizes(of: kids)
        return kids.map { ScanItem(url: $0, size: sizes[$0] ?? 0, category: "folder", selectedByDefault: false) }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
    }
}
