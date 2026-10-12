import Foundation

/// One event written by the hook script.
nonisolated struct AgentEvent: Sendable {
    let agent: AgentKind
    let name: String
    let sessionID: String?
    let cwd: String?
    let toolName: String?
    let message: String?
    let date: Date
}

/// Watches the inbox folder the hook script writes into and hands each event over once.
final class AgentEventInbox {
    var onEvents: ([AgentEvent]) -> Void = { _ in }

    private var source: DispatchSourceFileSystemObject?
    private var fallbackTimer: Timer?

    func start() {
        let directory = AgentHookInstaller.inboxDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        drain()

        let descriptor = open(directory.path, O_EVTONLY)
        if descriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.drain() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            self.source = source
        }

        // In case a directory event is missed.
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drain() }
        }
    }

    private func drain() {
        let directory = AgentHookInstaller.inboxDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let events = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> AgentEvent? in
                defer { try? FileManager.default.removeItem(at: url) }
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                return (try? Data(contentsOf: url)).flatMap { Self.parse($0, date: date) }
            }
            .sorted { $0.date < $1.date }

        if !events.isEmpty { onEvents(events) }
    }

    private nonisolated static func parse(_ data: Data, date: Date) -> AgentEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agent = (object["agent"] as? String).flatMap(AgentKind.init(rawValue:)),
              let name = object["event"] as? String
        else { return nil }

        let payload = object["payload"] as? [String: Any] ?? [:]
        return AgentEvent(
            agent: agent,
            name: name,
            sessionID: payload["session_id"] as? String ?? payload["thread-id"] as? String,
            cwd: payload["cwd"] as? String,
            toolName: payload["tool_name"] as? String,
            message: payload["message"] as? String ?? payload["last-assistant-message"] as? String,
            date: date
        )
    }
}
