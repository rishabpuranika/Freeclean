import ArgumentParser
import CleanCore
import Foundation

@main
struct FreeClean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "freeclean",
        abstract: "Free Mac cleaner. Everything removed goes to the Trash (except emptying the Trash itself).",
        subcommands: [Scan.self, Clean.self, Large.self, Uninstall.self, Disk.self, Memory.self, Startup.self],
        defaultSubcommand: Scan.self
    )
}

func confirm(_ prompt: String) -> Bool {
    print("\(prompt) [y/N] ", terminator: "")
    return ["y", "yes"].contains(readLine()?.lowercased() ?? "")
}

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
}

func lpad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : String(repeating: " ", count: n - s.count) + s
}

func printReport(_ r: TrashReport, dryRun: Bool) {
    let verb = dryRun ? "Would free" : "Freed"
    print("\n\(verb) \(Format.bytes(r.freed)) across \(r.trashed.count) item(s).")
    for (u, why) in r.failed { print("  ✗ \(u.path): \(why)") }
}

func tilde(_ u: URL) -> String {
    u.path.replacingOccurrences(of: Paths.home.path, with: "~")
}

extension JunkCategory: ExpressibleByArgument {}

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show reclaimable junk per category.")
    @Flag(name: .shortAndLong, help: "List individual items.") var verbose = false

    func run() async {
        let results = await JunkScanner().scanAll()
        var total: Int64 = 0
        for c in JunkCategory.allCases {
            let items = results[c] ?? []
            let size = items.totalSize
            if c.selectedByDefault { total += items.filter(\.selectedByDefault).totalSize }
            print("\(pad(c.title, 22)) \(lpad(Format.bytes(size), 10))  [\(c.rawValue)]\(c.selectedByDefault ? "" : "  (opt-in)")")
            if verbose {
                for i in items.prefix(15) { print("    \(lpad(Format.bytes(i.size), 10))  \(tilde(i.url))") }
            }
        }
        print("\nReclaimable by default: \(Format.bytes(total)). Run `freeclean clean` to clean.")
    }
}

struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Move junk to the Trash.")
    @Option(name: .shortAndLong, help: "Category to clean (repeatable): \(JunkCategory.allCases.map(\.rawValue).joined(separator: ", ")).")
    var category: [JunkCategory] = []
    @Flag(help: "Show what would be removed without touching anything.") var dryRun = false
    @Flag(name: .shortAndLong, help: "Don't ask for confirmation.") var yes = false

    func run() async throws {
        let cats = category.isEmpty ? JunkCategory.allCases.filter(\.selectedByDefault) : category
        let scanner = JunkScanner()
        let results = await scanner.scanAll(cats)
        // Explicitly requested categories include opt-in items (e.g. Xcode archives).
        let items = cats.flatMap { c in (results[c] ?? []).filter { category.isEmpty ? $0.selectedByDefault : true } }
        guard !items.isEmpty else { print("Nothing to clean."); return }
        for i in items { print("  \(lpad(Format.bytes(i.size), 10))  \(tilde(i.url))") }
        print("\n\(items.count) item(s), \(Format.bytes(items.totalSize)).")
        if cats.contains(.trash) { print("Note: the Trash category empties the Trash permanently.") }
        if !dryRun && !yes && !confirm("Move these to the Trash?") { throw ExitCode(1) }
        printReport(scanner.clean(items, dryRun: dryRun), dryRun: dryRun)
    }
}

struct Large: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Find large and old files in your home folder (read-only).")
    @Option(help: "Minimum size, e.g. 500M, 1G.") var minSize = "100M"
    @Option(help: "Also list files ≥10 MB not used for this many days (0 disables).") var olderThan = 365
    @Option(help: "Folder to scan.") var path: String?
    @Option(help: "Max rows to show.") var limit = 50
    @Flag(help: "Also look inside hidden folders (e.g. .dvc, .cache). .git and node_modules stay skipped.") var includeHidden = false

    func run() async throws {
        guard let min = Format.parseSize(minSize) else { throw ValidationError("Bad size: \(minSize)") }
        let root = path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? Paths.home
        var s = LargeFileScanner(root: root, minSize: min, olderThanDays: olderThan > 0 ? olderThan : nil)
        s.includeHidden = includeHidden
        print("Scanning \(tilde(root))…")
        let items = s.scan()
        for i in items.prefix(limit) {
            print("  \(lpad(Format.bytes(i.size), 10))  \(pad(i.category, 6))  \(pad(Format.date(i.modified), 14))  \(tilde(i.url))")
        }
        print("\n\(items.count) file(s), \(Format.bytes(items.totalSize)) total. Remove via Finder or the FreeClean app.")
    }
}

struct Uninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove an app and its leftovers (to the Trash). Omit name to list apps.")
    @Argument(help: "App name or bundle ID.") var app: String?
    @Flag(help: "Show what would be removed.") var dryRun = false
    @Flag(name: .shortAndLong, help: "Don't ask for confirmation.") var yes = false

    func run() async throws {
        let u = AppUninstaller()
        guard let app else {
            for a in u.listApps() { print("  \(pad(a.name, 32)) \(a.bundleID ?? "-")") }
            return
        }
        guard let target = u.findApp(named: app) else {
            print("App not found: \(app). Run `freeclean uninstall` to list apps.")
            throw ExitCode(1)
        }
        if target.isRunning { print("⚠️  \(target.name) is running — quit it first for a clean removal.") }
        let plan = await u.plan(for: target)
        for i in plan { print("  \(lpad(Format.bytes(i.size), 10))  \(pad(i.category, 9))  \(tilde(i.url))") }
        print("\nTotal \(Format.bytes(plan.totalSize)).")
        if !dryRun && !yes && !confirm("Move \(target.name) and its leftovers to the Trash?") { throw ExitCode(1) }
        printReport(u.uninstall(plan, dryRun: dryRun), dryRun: dryRun)
    }
}

struct Disk: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Disk space overview and biggest folders in your home.")
    @Option(help: "Folder to break down.") var path: String?

    func run() async {
        if let v = DiskUsage.volume() {
            let frac = Double(v.used) / Double(max(v.total, 1))
            let bar = String(repeating: "█", count: Int(frac * 40)) + String(repeating: "░", count: 40 - Int(frac * 40))
            print("Disk  \(bar)  \(Format.bytes(v.used)) used of \(Format.bytes(v.total)) — \(Format.bytes(v.availableImportant)) available")
        }
        let root = path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? Paths.home
        print("\nLargest in \(tilde(root)):")
        for i in await DiskUsage.breakdown(of: root).prefix(20) {
            print("  \(lpad(Format.bytes(i.size), 10))  \(i.name)")
        }
    }
}

struct Memory: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Memory usage and top processes.")
    @Option(help: "Number of processes.") var top = 15

    func run() {
        if let m = SystemInfo.memory() {
            let b: (UInt64) -> String = { Format.bytes(Int64($0)) }
            print("Memory used \(b(m.used)) of \(b(m.total)) (\(Int(m.usedFraction * 100))%)")
            print("  app \(b(m.active))  wired \(b(m.wired))  compressed \(b(m.compressed))  cached \(b(m.cached))  free \(b(m.free))")
        }
        print("\nTop processes by memory:")
        for p in SystemInfo.topProcesses(limit: top) {
            print("  \(lpad(Format.bytes(Int64(p.residentBytes)), 10))  \(lpad(String(p.pid), 6))  \(p.name)")
        }
    }
}

struct Startup: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List launch agents/daemons; optionally disable a user agent.")
    @Option(help: "Label of a user LaunchAgent to disable (plist goes to Trash).") var disable: String?

    func run() throws {
        let items = SystemInfo.loginItems()
        if let label = disable {
            guard let item = items.first(where: { $0.label == label }) else { print("No item with label \(label)"); throw ExitCode(1) }
            switch SystemInfo.disable(item) {
            case .success: print("Disabled \(label).")
            case .failure(let e): print("Failed: \(e.localizedDescription)"); throw ExitCode(1)
            }
            return
        }
        for i in items {
            print("  \(i.isUserOwned ? "user  " : "system")  \(i.runAtLoad ? "●" : "○")  \(pad(i.label, 45)) \(i.program)")
        }
        print("\n● = runs at load. Disable user items with `freeclean startup --disable <label>`.")
    }
}
