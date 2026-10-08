@testable import CleanCore
import Foundation

final class CleanCoreTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("freeclean-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func file(_ path: String, bytes: Int = 4096, modified: Date? = nil) throws -> URL {
        let u = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: u)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: u.path)
        }
        return u
    }

    func testParseSize() {
        expect(Format.parseSize("500M") == 500_000_000)
        expect(Format.parseSize("1.5G") == 1_500_000_000)
        expect(Format.parseSize("2048") == 2048)
        expect(Format.parseSize("abc") == nil)
    }

    func testFileSizerCountsTree() throws {
        try file("a/one", bytes: 10_000)
        try file("a/b/two", bytes: 20_000)
        expect(FileSizer.size(of: root.appendingPathComponent("a")) >= 30_000)
    }

    func testJunkScannerCategories() async throws {
        try file("Library/Caches/com.example.app/data", bytes: 50_000)
        try file("Library/Caches/Homebrew/pkg.tar.gz", bytes: 50_000)
        try file("Library/Logs/app.log")
        try file("Library/Developer/Xcode/DerivedData/Proj-abc/Build/x")
        try file("Library/Developer/Xcode/Archives/2024/x.xcarchive/y")
        try file("Downloads/old.zip", modified: Date().addingTimeInterval(-200 * 86_400))
        try file("Downloads/new.zip")

        let r = await JunkScanner(home: root).scanAll()
        expect(r[.userCaches]?.map(\.name) == ["com.example.app"], "Homebrew belongs to dev caches")
        expect(r[.devCaches]?.map(\.name) == ["Homebrew"])
        expect(r[.logs]?.count == 1)
        let xcode = r[.xcode] ?? []
        expect(xcode.contains { $0.name == "Proj-abc" && $0.selectedByDefault })
        expect(xcode.contains { $0.name == "2024" && !$0.selectedByDefault }, "archives are opt-in")
        expect(r[.oldDownloads]?.map(\.name) == ["old.zip"])
    }

    func testLargeFileScanner() throws {
        try file("big.bin", bytes: 3_000_000)
        try file("small.txt", bytes: 100)
        try file("node_modules/huge.bin", bytes: 3_000_000)
        let items = LargeFileScanner(root: root, minSize: 2_000_000, olderThanDays: nil).scan()
        expect(items.map(\.name) == ["big.bin"])
    }

    func testUninstallerFindsLeftovers() throws {
        let app = root.appendingPathComponent("Applications/Foo.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: NSDictionary = ["CFBundleIdentifier": "com.example.foo", "CFBundleName": "Foo"]
        plist.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        try file("Library/Preferences/com.example.foo.plist")
        try file("Library/Application Support/Foo/db")
        try file("Library/Caches/com.example.foo/x")
        try file("Library/Group Containers/TEAM.com.example.foo/x")
        try file("Library/Application Support/FooBar/db")  // must not match

        let u = AppUninstaller(home: root, appDirs: [root.appendingPathComponent("Applications")])
        let found = try require(u.findApp(named: "foo"))
        let names = Set(u.leftovers(for: found).map(\.lastPathComponent))
        expect(names == ["com.example.foo.plist", "Foo", "com.example.foo", "TEAM.com.example.foo"])
    }

    func testSafetyGuard() {
        expect(!Paths.isSafeToTrash(Paths.home))
        expect(!Paths.isSafeToTrash(Paths.home.appendingPathComponent("Library")))
        expect(!Paths.isSafeToTrash(URL(fileURLWithPath: "/System/Library")))
        expect(Paths.isSafeToTrash(Paths.home.appendingPathComponent("Library/Caches/foo")))
    }

    func testTrashRefusesOutsideHomeAndDryRunTouchesNothing() throws {
        let f = try file("x.bin")
        let r = Trash.move([ScanItem(url: f, size: 10, category: "t"),
                            ScanItem(url: URL(fileURLWithPath: "/etc/hosts"), size: 1, category: "t")], dryRun: true)
        expect(r.failed.contains { $0.0.path == "/etc/hosts" }, "/etc/hosts must be refused")
        expect(FileManager.default.fileExists(atPath: f.path))
    }

    func testSystemInfo() {
        expect(SystemInfo.memory() != nil)
        expect(!SystemInfo.topProcesses(limit: 5).isEmpty)
        expect(DiskUsage.volume() != nil)
    }

    /// Real round trip: a throwaway file in ~/Library/Caches goes to ~/.Trash, then is removed from there.
    func testRealMoveToTrash() throws {
        let dir = Paths.library.appendingPathComponent("Caches/freeclean-selftest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1000).write(to: dir.appendingPathComponent("junk"))
        let r = Trash.move([ScanItem(url: dir, size: 1000, category: "t")])
        expect(r.failed.isEmpty, "\(r.failed)")
        expect(!FileManager.default.fileExists(atPath: dir.path), "original should be gone")
        let inTrash = FileSizer.children(of: Paths.home.appendingPathComponent(".Trash"))
            .filter { $0.lastPathComponent.hasPrefix(dir.lastPathComponent) }
        expect(!inTrash.isEmpty || r.failed.isEmpty, "should be in Trash (unreadable without Full Disk Access)")
        for u in inTrash { try? FileManager.default.removeItem(at: u) }
    }
}
