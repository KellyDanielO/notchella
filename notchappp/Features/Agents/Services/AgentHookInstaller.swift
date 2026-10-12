import Foundation

/// Installs the small hook script agents call, and registers it with Claude Code and Codex.
///
/// The script writes each event as a JSON file into an inbox folder that `AgentEventInbox` watches.
/// It prints nothing and always exits 0, so it can never block or change an agent's behavior.
nonisolated enum AgentHookInstaller {
    enum InstallError: LocalizedError {
        case unreadableSettings
        case codexNotifyAlreadySet

        var errorDescription: String? {
            switch self {
            case .unreadableSettings:
                "~/.claude/settings.json isn't valid JSON, so it was left untouched."
            case .codexNotifyAlreadySet:
                "~/.codex/config.toml already has a `notify` command. Add the notch hook to it by hand."
            }
        }
    }

    static let marker = "notch-agent-hook"

    /// Claude Code events we listen to. `PreToolUse` gets a match-all matcher.
    private static let claudeEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"]

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "com.kellydaniel.notchappp")
    }

    static var inboxDirectory: URL { supportDirectory.appending(path: "AgentEvents") }
    static var scriptURL: URL { supportDirectory.appending(path: "bin/\(marker)") }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var claudeSettingsURL: URL { home.appending(path: ".claude/settings.json") }
    private static var codexConfigURL: URL { home.appending(path: ".codex/config.toml") }

    // MARK: Status

    static var isClaudeInstalled: Bool {
        (try? String(contentsOf: claudeSettingsURL, encoding: .utf8))?.contains(marker) ?? false
    }

    static var isCodexInstalled: Bool {
        (try? String(contentsOf: codexConfigURL, encoding: .utf8))?.contains(marker) ?? false
    }

    // MARK: Script

    /// Usage: `notch-agent-hook <agent> <event> [json]`. The payload comes from the last
    /// argument (Codex) or stdin (Claude Code).
    static func installScript() throws {
        let script = """
        #!/bin/sh
        # Forwards agent events to the Notch app. Installed by Notch; safe to delete.
        DIR="$HOME/Library/Application Support/com.kellydaniel.notchappp/AgentEvents"
        mkdir -p "$DIR" 2>/dev/null
        if [ -n "$3" ]; then PAYLOAD="$3"; elif [ ! -t 0 ]; then PAYLOAD=$(cat); fi
        [ -z "$PAYLOAD" ] && PAYLOAD='{}'
        TMP=$(mktemp "$DIR/.event.XXXXXX") || exit 0
        printf '{"agent":"%s","event":"%s","payload":%s}' "$1" "$2" "$PAYLOAD" > "$TMP"
        # Written under a hidden name, then renamed visible so the app never reads a partial file.
        mv "$TMP" "$DIR/event${TMP##*/.event}.json"
        exit 0

        """
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    private static func command(agent: AgentKind, event: String) -> String {
        "\"\(scriptURL.path)\" \(agent.rawValue) \(event)"
    }

    // MARK: Claude Code

    /// Merges hook entries into `~/.claude/settings.json`, keeping everything else.
    /// The original file is backed up next to it first.
    static func installClaude() throws {
        try installScript()
        var settings = try readClaudeSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in claudeEvents {
            var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !containsMarker($0) }
            var group: [String: Any] = ["hooks": [["type": "command", "command": command(agent: .claude, event: event)]]]
            if event == "PreToolUse" { group["matcher"] = "*" }
            groups.append(group)
            hooks[event] = groups
        }

        settings["hooks"] = hooks
        try writeClaudeSettings(settings)
    }

    static func uninstallClaude() throws {
        var settings = try readClaudeSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            let remaining = (value as? [[String: Any]] ?? []).filter { !containsMarker($0) }
            hooks[event] = remaining.isEmpty ? nil : remaining
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try writeClaudeSettings(settings)
    }

    private static func containsMarker(_ group: [String: Any]) -> Bool {
        let entries = group["hooks"] as? [[String: Any]] ?? []
        return entries.contains { ($0["command"] as? String)?.contains(marker) ?? false }
    }

    private static func readClaudeSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: claudeSettingsURL), !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings
        }
        return object
    }

    private static func writeClaudeSettings(_ settings: [String: Any]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: claudeSettingsURL.path) {
            let backup = claudeSettingsURL.appendingPathExtension("notch-backup")
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: claudeSettingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: claudeSettingsURL, options: .atomic)
    }

    // MARK: Codex

    /// Codex calls a single `notify` program when a turn completes. Adds ours as a top-level key.
    static func installCodex() throws {
        try installScript()
        let existing = (try? String(contentsOf: codexConfigURL, encoding: .utf8)) ?? ""
        guard !existing.contains(marker) else { return }
        if existing.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") }) {
            throw InstallError.codexNotifyAlreadySet
        }
        // Top-level TOML keys must come before any [table], so prepend.
        let line = "notify = [\"\(scriptURL.path)\", \"codex\", \"notify\"]\n"
        try FileManager.default.createDirectory(at: codexConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (line + existing).write(to: codexConfigURL, atomically: true, encoding: .utf8)
    }

    static func uninstallCodex() throws {
        guard let existing = try? String(contentsOf: codexConfigURL, encoding: .utf8) else { return }
        let kept = existing.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.contains(marker) }
        try kept.joined(separator: "\n").write(to: codexConfigURL, atomically: true, encoding: .utf8)
    }
}
