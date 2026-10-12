import SwiftUI

/// Xcode builds, agent sessions, and the keep-awake control, shown in the Dev tab.
struct AgentsPanel: View {
    @Environment(AgentMonitor.self) private var agents
    @Environment(KeepAwakeManager.self) private var keepAwake
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                keepAwakeMenu
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    XcodeBuildRow()
                    ForEach(agents.sessions) { session in
                        AgentSessionRow(session: session)
                    }
                    if agents.sessions.isEmpty {
                        emptyState
                    }
                }
            }
        }
    }

    /// Cycles Off → While agents work → Always. A plain SwiftUI button rather than a `Menu`:
    /// a bridged pop-up button whose label width changes can loop AppKit's constraint passes.
    private var keepAwakeMenu: some View {
        Button {
            let modes = KeepAwakeManager.Mode.allCases
            let next = modes[(modes.firstIndex(of: settings.keepAwakeMode)! + 1) % modes.count]
            withAnimation(.smooth(duration: 0.2)) { settings.keepAwakeMode = next }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: keepAwake.isHoldingAssertion ? "cup.and.heat.waves.fill" : "moon.zzz.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(keepAwakeLabel)
                    .font(.system(size: 10.5, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(keepAwake.isHoldingAssertion ? .black : .white.opacity(0.7))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(keepAwake.isHoldingAssertion ? Color.yellow : .white.opacity(0.1)))
        }
        .buttonStyle(PressableButtonStyle())
        .help("Keep Mac awake: \(settings.keepAwakeMode.title). Click to change.")
    }

    private var keepAwakeLabel: String {
        switch settings.keepAwakeMode {
        case .off: "Sleep allowed"
        case .always: "Always awake"
        case .whileAgentsWork: keepAwake.isHoldingAssertion ? "Awake: agent working" : "Awake while agents work"
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No agents running")
                .font(.system(size: 12, weight: .semibold))
            Text(agents.hooksInstalled[.claude] == true
                 ? "Start a Claude Code session and it shows up here."
                 : "Install the Claude Code hooks in Settings for live status.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 2)
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 8) {
            AgentStatusDot(kind: session.kind, state: session.state)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.project)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(session.state == .needsInput ? .orange : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if session.state == .working {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date.timeIntervalSince(session.stateSince).countdownText)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(session.kind.tint)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.06)))
    }

    private var statusText: String {
        let agent = session.kind.displayName
        switch session.state {
        case .working:
            if case .process = session.source { return "\(agent) · busy (estimated)" }
            return session.detail.map { "\(agent) · \($0)" } ?? "\(agent) · working"
        case .needsInput:
            return session.detail ?? "Needs your input"
        case .idle:
            return "\(agent) · idle"
        }
    }
}

/// A dot in the agent's color that pulses while working.
struct AgentStatusDot: View {
    let kind: AgentKind
    let state: AgentSession.State
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(state == .needsInput ? .orange : (state == .idle ? .white.opacity(0.3) : kind.tint))
            .frame(width: size, height: size)
            .overlay {
                if state != .idle {
                    Circle()
                        .stroke(state == .needsInput ? .orange : kind.tint, lineWidth: 1.5)
                        .phaseAnimator([false, true]) { circle, expanded in
                            circle
                                .scaleEffect(expanded ? 2.2 : 1)
                                .opacity(expanded ? 0 : 0.8)
                        } animation: { _ in .easeOut(duration: 1.2) }
                }
            }
    }
}

/// Closed-notch content for agents: what's on the left wing and the right wing.
struct AgentClosedLeading: View {
    @Environment(AgentMonitor.self) private var agents

    var body: some View {
        if let finished = agents.justFinished {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.green)
                .help("\(finished.kind.displayName) finished in \(finished.project)")
        } else if let waiting = agents.sessionNeedingInput {
            AgentStatusDot(kind: waiting.kind, state: .needsInput, size: 9)
        } else if let working = agents.workingSessions.first {
            AgentStatusDot(kind: working.kind, state: .working, size: 9)
        }
    }
}

struct AgentClosedTrailing: View {
    @Environment(AgentMonitor.self) private var agents

    var body: some View {
        Group {
            if let finished = agents.justFinished {
                Text(finished.project)
                    .foregroundStyle(.green)
            } else if agents.sessionNeedingInput != nil {
                Text("Input")
                    .foregroundStyle(.orange)
            } else if let since = agents.workingSince {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 3) {
                        if agents.workingSessions.count > 1 {
                            Text("\(agents.workingSessions.count)×")
                                .foregroundStyle(.secondary)
                        }
                        Text(context.date.timeIntervalSince(since).countdownText)
                            .foregroundStyle(agents.workingSessions.first?.kind.tint ?? .white)
                    }
                }
            }
        }
        .font(.system(size: 12, weight: .bold).monospacedDigit())
        .lineLimit(1)
    }
}
