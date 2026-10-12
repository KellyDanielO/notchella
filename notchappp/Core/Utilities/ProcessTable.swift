import Darwin
import Foundation

/// Thin wrappers over libproc and sysctl for inspecting other processes.
nonisolated enum ProcessTable {
    struct Entry: Sendable {
        let pid: Int32
        let parentPID: Int32
        let name: String
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Every process with its parent and short name.
    static func snapshot() -> [Entry] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))

        return pids.prefix(Int(max(filled, 0))).compactMap { pid -> Entry? in
            guard pid > 0 else { return nil }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            let name = withUnsafeBytes(of: info.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return Entry(pid: pid, parentPID: Int32(info.pbi_ppid), name: name)
        }
    }

    /// Maps each process to its direct children.
    static func childrenMap(_ entries: [Entry]) -> [Int32: [Int32]] {
        var children: [Int32: [Int32]] = [:]
        for entry in entries { children[entry.parentPID, default: []].append(entry.pid) }
        return children
    }

    /// All descendants of `pid`, not including `pid` itself.
    static func descendants(of pid: Int32, in children: [Int32: [Int32]]) -> [Int32] {
        var result: [Int32] = []
        var stack = children[pid] ?? []
        while let next = stack.popLast() {
            result.append(next)
            stack.append(contentsOf: children[next] ?? [])
        }
        return result
    }

    /// Total user + system CPU time, in nanoseconds.
    static func cpuTime(of pid: Int32) -> UInt64 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return 0 }
        let ticks = info.pti_total_user + info.pti_total_system
        return ticks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
    }

    static func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }

    /// The command-line arguments of a process owned by the same user.
    static func arguments(of pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }

        // Layout: argc, the executable path, NUL padding, then argc NUL-terminated arguments.
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        var start = index
        while index < size && arguments.count < Int(argc) {
            if buffer[index] == 0 {
                arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
                start = index + 1
            }
            index += 1
        }
        return arguments
    }
}
