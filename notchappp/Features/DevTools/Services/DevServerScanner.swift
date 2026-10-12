import AppKit
import SwiftUI

nonisolated struct DevServer: Identifiable, Equatable, Sendable {
    var id: Int { port }
    let port: Int
    let processName: String
    let pid: Int32

    var url: URL { URL(string: "http://localhost:\(port)")! }
}

/// Lists local servers listening on TCP ports, so dev servers are one click away.
/// Scans only while the Dev tab is visible.
@Observable
final class DevServerScanner {
    private(set) var servers: [DevServer] = []

    /// System and app services that listen locally but aren't dev servers.
    private nonisolated static let ignoredProcesses: Set<String> = [
        "rapportd", "ControlCe", "ControlCenter", "Spotify", "sharingd", "identitys",
        "launchd", "mDNSRespo", "AirPlayXP", "remoted", "Claude", "Code\\x20H", "Code Helper",
    ]

    func refresh() async {
        let output = await Task.detached(priority: .utility) { Self.runLsof() }.value
        let parsed = Self.parse(output ?? "")
        if parsed != servers {
            withAnimation(.smooth) { servers = parsed }
        }
    }

    func open(_ server: DevServer) {
        NSWorkspace.shared.open(server.url)
    }

    /// Asks the server to quit (SIGTERM), then force-quits it (SIGKILL) if it's still
    /// running two seconds later, which dev servers ignoring SIGTERM sometimes need.
    func stop(_ server: DevServer) {
        let pid = server.pid
        guard pid > 0, kill(pid, SIGTERM) == 0 else { return }
        withAnimation(.smooth) { servers.removeAll { $0.pid == pid } }

        Task {
            try? await Task.sleep(for: .seconds(2))
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            await refresh()
        }
    }

    private nonisolated static func runLsof() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Parses `lsof -F pcn` output: `p<pid>`, `c<command>`, then `n<address:port>` lines.
    private nonisolated static func parse(_ output: String) -> [DevServer] {
        var servers: [Int: DevServer] = [:]
        var pid: Int32 = 0
        var command = ""

        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                guard let portText = value.split(separator: ":").last, let port = Int(portText),
                      port >= 1024, !ignoredProcesses.contains(command)
                else { continue }
                servers[port] = DevServer(port: port, processName: command, pid: pid)
            default:
                break
            }
        }
        return servers.values.sorted { $0.port < $1.port }
    }
}
