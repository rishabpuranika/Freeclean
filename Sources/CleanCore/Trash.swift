import Foundation

public struct TrashReport: Sendable {
    public var trashed: [URL] = []
    public var failed: [(URL, String)] = []
    public var freed: Int64 = 0

    public init() {}
}

public enum Trash {
    /// Moves items to the user's Trash (recoverable). Never deletes permanently.
    public static func move(_ items: [ScanItem], dryRun: Bool = false) -> TrashReport {
        var report = TrashReport()
        for item in items {
            guard Paths.isSafeToTrash(item.url) else {
                report.failed.append((item.url, "refused: outside safe locations"))
                continue
            }
            guard FileManager.default.fileExists(atPath: item.url.path) else { continue }
            if dryRun {
                report.trashed.append(item.url)
                report.freed += item.size
                continue
            }
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                report.trashed.append(item.url)
                report.freed += item.size
            } catch {
                report.failed.append((item.url, error.localizedDescription))
            }
        }
        return report
    }

    /// Permanently empties ~/.Trash. Callers must confirm with the user first.
    public static func empty() -> TrashReport {
        var report = TrashReport()
        let trash = Paths.home.appendingPathComponent(".Trash")
        for child in FileSizer.children(of: trash) {
            let size = FileSizer.size(of: child)
            do {
                try FileManager.default.removeItem(at: child)
                report.trashed.append(child)
                report.freed += size
            } catch {
                report.failed.append((child, error.localizedDescription))
            }
        }
        return report
    }
}
