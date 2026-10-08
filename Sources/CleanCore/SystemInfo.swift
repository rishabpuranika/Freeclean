import Darwin
import Foundation

public struct MemoryStats: Sendable {
    public let total: UInt64
    public let free: UInt64
    public let active: UInt64
    public let inactive: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let cached: UInt64
    /// Roughly what Activity Monitor calls "Memory Used" (app + wired + compressed).
    public var used: UInt64 { active + wired + compressed }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct ProcessUsage: Identifiable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let residentBytes: UInt64
}

public struct LoginItem: Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let label: String
    public let program: String
    public let runAtLoad: Bool
    public let isUserOwned: Bool
}

public enum SystemInfo {
    public static func memory() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        return MemoryStats(
            total: ProcessInfo.processInfo.physicalMemory,
            free: UInt64(stats.free_count) * page,
            active: (internalPages > purgeable ? internalPages - purgeable : internalPages) * page,
            inactive: UInt64(stats.inactive_count) * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            cached: (UInt64(stats.external_page_count) + purgeable) * page
        )
    }

    public static func topProcesses(limit: Int = 15) -> [ProcessUsage] {
        let maxCount = proc_listallpids(nil, 0)
        guard maxCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(maxCount) * 2)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var out: [ProcessUsage] = []
        for pid in pids.prefix(Int(max(n, 0))) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            var nameBuf = [CChar](repeating: 0, count: 1024)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            var name = String(cString: nameBuf)
            // proc_name truncates at 32 chars (MAXCOMLEN); fall back to the executable path for long names.
            if name.isEmpty || name.utf8.count >= 31 {
                var pathBuf = [CChar](repeating: 0, count: 4096)
                proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
                let full = URL(fileURLWithPath: String(cString: pathBuf)).lastPathComponent
                if !full.isEmpty { name = full }
            }
            out.append(ProcessUsage(pid: pid, name: name, residentBytes: info.pti_resident_size))
        }
        return Array(out.sorted { $0.residentBytes > $1.residentBytes }.prefix(limit))
    }

    public static func loginItems(home: URL = Paths.home) -> [LoginItem] {
        let dirs: [(URL, Bool)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), true),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), false),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), false),
        ]
        var out: [LoginItem] = []
        for (dir, userOwned) in dirs {
            for f in FileSizer.children(of: dir) where f.pathExtension == "plist" {
                let d = NSDictionary(contentsOf: f) as? [String: Any] ?? [:]
                let program = (d["Program"] as? String) ?? (d["ProgramArguments"] as? [String])?.first ?? "-"
                out.append(LoginItem(url: f, label: (d["Label"] as? String) ?? f.deletingPathExtension().lastPathComponent,
                                     program: program, runAtLoad: (d["RunAtLoad"] as? Bool) ?? false,
                                     isUserOwned: userOwned))
            }
        }
        return out
    }

    /// Unloads a user LaunchAgent and moves its plist to the Trash. System agents are refused.
    @discardableResult
    public static func disable(_ item: LoginItem) -> Result<Void, Error> {
        guard item.isUserOwned else {
            return .failure(NSError(domain: "FreeClean", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "System-wide items need admin rights; remove them manually."]))
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())", item.url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()  // non-zero just means it wasn't loaded
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
