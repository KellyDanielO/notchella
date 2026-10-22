import AppKit
import SwiftUI

/// Tracks coding-agent sessions (Claude Code, Codex) and whether any of them is working.
///
/// Two sources feed it:
/// - Hook events (precise): prompt submitted → working, tool use → working,
///   needs permission → needs input, stop → finished.
/// - Process CPU (approximate, no setup): used only for agents without hooks installed.
///   A busy process tree counts as working, held for a few minutes to bridge quiet stretches.
@Observable
final class AgentMonitor {
    private(set) var sessions: [AgentSession] = []
    /// A session that just finished, shown briefly in the notch.
    private(set) var justFinished: AgentSession?
    /// Minutes of continuous agent work, set while the "take a break" nudge is showing.
    private(set) var breakNudgeMinutes: Int?
    private(set) var hooksInstalled: [AgentKind: Bool] = [:]

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let inbox = AgentEventInbox()
    @ObservationIgnored private let scanner = AgentProcessScanner()
    @ObservationIgnored private let scanQueue = DispatchQueue(label: "com.kellydaniel.notchappp.agents", qos: .utility)
    @ObservationIgnored private var scanTimer: Timer?
    @ObservationIgnored private var finishedTask: Task<Void, Never>?
    @ObservationIgnored private var processActivity: [Int32: Date] = [:]
    /// Agents whose lifecycle hooks have actually fired. Codex skips hooks you haven't reviewed
    /// in it yet, and `notify` alone only reports finished turns, so CPU stays in use until then.
    @ObservationIgnored private var agentsReportingHooks: Set<AgentKind> = []
    @ObservationIgnored private var workStretchStart: Date?
    @ObservationIgnored private var lastWorkingDate: Date?
    @ObservationIgnored private var nudgesThisStretch = 0
    @ObservationIgnored private var breakNudgeTask: Task<Void, Never>?

    /// A gap without any agent working longer than this ends a work stretch.
    private static let stretchBreakGap: TimeInterval = 5 * 60

    /// CPU use (percent of a core) above which an agent's process tree counts as busy.
    private static let busyCPUThreshold = 3.0
    /// How long a process keeps counting as working after its last busy sample.
    private static let processHoldTime: TimeInterval = 180
    /// Hook sessions with no events for this long are assumed done (e.g. the agent crashed).
    private static let staleWorkingTime: TimeInterval = 20 * 60

    init(settings: AppSettings) {
        self.settings = settings
        refreshHookStatus()
    }

    func start() {
        inbox.onEvents = { [weak self] events in self?.apply(events) }
        inbox.start()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanProcesses() }
        }
        scanProcesses()
    }

    var workingSessions: [AgentSession] { sessions.filter { $0.state == .working } }
    var isAnyWorking: Bool { sessions.contains { $0.state == .working } }
    var sessionNeedingInput: AgentSession? { sessions.first { $0.state == .needsInput } }

    /// When the earliest working session started, for the elapsed time in the notch.
    var workingSince: Date? { workingSessions.map(\.stateSince).min() }

    func refreshHookStatus() {
        hooksInstalled = [
            .claude: AgentHookInstaller.isClaudeInstalled,
            .codex: AgentHookInstaller.isCodexInstalled,
        ]
    }

    func dismissBreakNudge() {
        breakNudgeTask?.cancel()
        withAnimation(.notchActivity) { breakNudgeMinutes = nil }
    }

    /// Tracks continuous stretches of agent work (short pauses between prompts don't count as
    /// breaks) and nudges you to take one every `agentBreakMinutes`.
    private func checkBreakNudge() {
        let now = Date()
        if isAnyWorking {
            if workStretchStart == nil || now.timeIntervalSince(lastWorkingDate ?? now) > Self.stretchBreakGap {
                workStretchStart = now
                nudgesThisStretch = 0
            }
            lastWorkingDate = now
        }
        guard settings.agentBreakNudge, let start = workStretchStart, isAnyWorking else { return }

        let interval = TimeInterval(max(settings.agentBreakMinutes, 5) * 60)
        let due = Int(now.timeIntervalSince(start) / interval)
        guard due > nudgesThisStretch else { return }
        nudgesThisStretch = due

        if settings.alertSoundEnabled { NSSound(named: "Blow")?.play() }
        breakNudgeTask?.cancel()
        withAnimation(.notchActivity) { breakNudgeMinutes = Int(now.timeIntervalSince(start) / 60) }
        breakNudgeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.dismissBreakNudge()
        }
    }

    func dismissFinished() {
        finishedTask?.cancel()
        withAnimation(.notchActivity) { justFinished = nil }
    }

    // MARK: Hook events

    private func apply(_ events: [AgentEvent]) {
        for event in events {
            let id = "\(event.agent.rawValue):\(event.sessionID ?? "default")"
            let project = event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            var session = sessions.first { $0.id == id } ?? AgentSession(
                id: id,
                kind: event.agent,
                project: project ?? event.agent.displayName,
                state: .idle,
                stateSince: event.date,
                lastEvent: event.date,
                source: .hooks
            )
            if let project { session.project = project }
            session.lastEvent = event.date
            if event.name != "notify" { agentsReportingHooks.insert(event.agent) }

            switch event.name {
            case "SessionStart":
                break
            case "UserPromptSubmit", "PreToolUse":
                if session.state != .working { session.stateSince = event.date }
                session.state = .working
                session.detail = event.toolName
            case "Notification", "PermissionRequest":
                session.state = .needsInput
                session.stateSince = event.date
                session.detail = event.message
            case "Stop", "notify":
                let wasWorking = session.state == .working
                session.state = .idle
                session.stateSince = event.date
                session.detail = nil
                // Codex sends both `Stop` and `notify` for a turn once its hooks run; announce once.
                if wasWorking || (event.name == "notify" && !agentsReportingHooks.contains(event.agent)) {
                    announceFinished(session)
                }
            case "SessionEnd":
                withAnimation(.notchActivity) { sessions.removeAll { $0.id == id } }
                continue
            default:
                break
            }
            upsert(session)
        }
    }

    private func announceFinished(_ session: AgentSession) {
        guard settings.agentFinishAlerts else { return }
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if settings.alertSoundEnabled { NSSound(named: "Glass")?.play() }

        finishedTask?.cancel()
        withAnimation(.notchActivity) { justFinished = session }
        finishedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.notchActivity) { self?.justFinished = nil }
        }
    }

    private func upsert(_ session: AgentSession) {
        withAnimation(.notchActivity) {
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            } else {
                sessions.append(session)
            }
        }
    }

    // MARK: Process heuristic

    private func scanProcesses() {
        checkBreakNudge()
        expireStaleSessions()
        let scanner = scanner
        scanQueue.async { [weak self] in
            let processes = scanner.scan()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.applyProcesses(processes) }
            }
        }
    }

    private func applyProcesses(_ processes: [AgentProcess]) {
        let now = Date()
        // Agents with hooks report precisely; don't second-guess them with CPU numbers.
        let tracked = processes.filter { hooksInstalled[$0.kind] != true || !agentsReportingHooks.contains($0.kind) }

        for process in tracked where process.cpuPercent >= Self.busyCPUThreshold {
            processActivity[process.pid] = now
        }
        let livePIDs = Set(tracked.map(\.pid))
        processActivity = processActivity.filter { livePIDs.contains($0.key) && now.timeIntervalSince($0.value) < Self.processHoldTime }

        var updated = sessions.filter { $0.source == .hooks }
        for process in tracked {
            guard processActivity[process.pid] != nil else { continue }
            let id = "pid:\(process.pid)"
            let previous = sessions.first { $0.id == id }
            updated.append(AgentSession(
                id: id,
                kind: process.kind,
                project: process.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? process.kind.displayName,
                state: .working,
                stateSince: previous?.stateSince ?? now,
                lastEvent: now,
                detail: nil,
                source: .process(pid: process.pid)
            ))
        }

        if updated != sessions {
            withAnimation(.notchActivity) { sessions = updated }
        }
    }

    private func expireStaleSessions() {
        let now = Date()
        var changed = false
        var updated = sessions
        for index in updated.indices where updated[index].source == .hooks {
            if updated[index].state == .working && now.timeIntervalSince(updated[index].lastEvent) > Self.staleWorkingTime {
                updated[index].state = .idle
                changed = true
            }
        }
        // Forget idle hook sessions after an hour.
        let before = updated.count
        updated.removeAll { $0.source == .hooks && $0.state == .idle && now.timeIntervalSince($0.lastEvent) > 3600 }
        if changed || updated.count != before {
            withAnimation(.notchActivity) { sessions = updated }
        }
    }
}
