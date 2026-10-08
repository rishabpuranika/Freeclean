import Foundation

// Minimal test runner: XCTest and Swift Testing's macros only ship with full Xcode,
// so this lets `swift run freeclean-selftest` work with Command Line Tools alone.
nonisolated(unsafe) var failures = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "", file: String = #fileID, line: Int = #line) {
    if !condition() {
        failures += 1
        print("    ✗ \(file):\(line) \(message)")
    }
}

struct RequireError: Error {}

func require<T>(_ value: T?, file: String = #fileID, line: Int = #line) throws -> T {
    guard let value else {
        print("    ✗ \(file):\(line) required value was nil")
        failures += 1
        throw RequireError()
    }
    return value
}

let tests: [(String, (CleanCoreTests) async throws -> Void)] = [
    ("parseSize", { $0.testParseSize() }),
    ("fileSizerCountsTree", { try $0.testFileSizerCountsTree() }),
    ("junkScannerCategories", { try await $0.testJunkScannerCategories() }),
    ("largeFileScanner", { try $0.testLargeFileScanner() }),
    ("uninstallerFindsLeftovers", { try $0.testUninstallerFindsLeftovers() }),
    ("safetyGuard", { $0.testSafetyGuard() }),
    ("trashRefusesOutsideHomeAndDryRun", { try $0.testTrashRefusesOutsideHomeAndDryRunTouchesNothing() }),
    ("systemInfo", { $0.testSystemInfo() }),
    ("realMoveToTrash", { try $0.testRealMoveToTrash() }),
]

for (name, body) in tests {
    let before = failures
    do { try await body(CleanCoreTests()) } catch { failures += 1; print("    ✗ threw \(error)") }
    print("\(failures == before ? "✓" : "✗") \(name)")
}
print(failures == 0 ? "\nAll \(tests.count) tests passed." : "\n\(failures) failure(s).")
exit(failures == 0 ? 0 : 1)
