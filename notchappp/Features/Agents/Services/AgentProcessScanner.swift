import Foundation

/// A running agent process and how busy its whole process tree is.
nonisolated struct AgentProcess: Sendable {
    let pid: Int32
    let kind: AgentKind
    let workingDirectory: String?
    /// CPU use of the process and all its descendants since the previous scan, in percent of one core.
    let cpuPercent: Double
}

/// Finds agent processes and measures their tree's CPU use. It needs no setup, but it's only a
/// heuristic: an agent waiting on a slow model reply looks idle.
nonisolated final class AgentProcessScanner: @unchecked Sendable {
    private var previousCPU: [Int32: UInt64] = [:]
    private var previousDate: Date?

    /// Call from one queue only.
    func scan() -> [AgentProcess] {
        let entries = ProcessTable.snapshot()
        let children = ProcessTable.childrenMap(entries)
        let agents = entries.compactMap { entry -> (Int32, AgentKind)? in
            AgentKind.allCases
                .first { kind in kind.processNames.contains { entry.name.hasPrefix($0) } }
                .map { (entry.pid, $0) }
        }

        let now = Date()
        let interval = previousDate.map { now.timeIntervalSince($0) } ?? 0
        var currentCPU: [Int32: UInt64] = [:]

        // Children of each agent (shells, test runners, builds) count toward its activity.
        let results = agents.map { pid, kind -> AgentProcess in
            var total: UInt64 = 0
            var previousTotal: UInt64 = 0
            for member in [pid] + ProcessTable.descendants(of: pid, in: children) {
                let cpu = ProcessTable.cpuTime(of: member)
                currentCPU[member] = cpu
                total += cpu
                previousTotal += previousCPU[member] ?? cpu
            }
            let delta = total > previousTotal ? Double(total - previousTotal) : 0
            let percent = interval > 0 ? delta / 1_000_000_000 / interval * 100 : 0
            return AgentProcess(pid: pid, kind: kind, workingDirectory: ProcessTable.workingDirectory(of: pid), cpuPercent: percent)
        }

        previousCPU = currentCPU
        previousDate = now
        return results
    }
}
