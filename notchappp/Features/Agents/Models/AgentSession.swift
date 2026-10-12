import SwiftUI

nonisolated enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.55, green: 0.75, blue: 1)
        }
    }

    /// Executable names used to spot the agent's process.
    var processNames: [String] {
        switch self {
        case .claude: ["claude"]
        case .codex: ["codex"]
        }
    }
}

nonisolated struct AgentSession: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case working
        case needsInput
        case idle
    }

    /// How the session is known: precise hook events, or CPU activity of its process.
    enum Source: Equatable, Sendable {
        case hooks
        case process(pid: Int32)
    }

    let id: String
    let kind: AgentKind
    var project: String
    var state: State
    var stateSince: Date
    var lastEvent: Date
    /// The tool being run, or the message when the agent needs input.
    var detail: String?
    var source: Source
}
