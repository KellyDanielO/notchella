import SwiftUI

/// The Dev tab: agent sessions on the left, local servers and quick tools on the right.
struct DevView: View {
    var body: some View {
        HStack(spacing: 0) {
            AgentsPanel()
                .frame(width: 262)
                .padding(.trailing, 16)
                .staggeredAppear(0)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 12) {
                DevServersSection()
                DevToolsRow()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 16)
            .staggeredAppear(1)
        }
    }
}

private struct DevServersSection: View {
    @Environment(DevServerScanner.self) private var scanner

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Localhost")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            if scanner.servers.isEmpty {
                Text("No dev servers running")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(scanner.servers) { server in
                            DevServerChip(server: server)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        // Scan only while the tab is on screen.
        .task {
            while !Task.isCancelled {
                await scanner.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}

/// A localhost server: click to open it, ✕ to stop it (click again to confirm).
private struct DevServerChip: View {
    let server: DevServer

    @Environment(DevServerScanner.self) private var scanner
    @State private var isConfirmingStop = false

    var body: some View {
        HStack(spacing: 6) {
            Button { scanner.open(server) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(":" + String(server.port))
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                    Text(isConfirmingStop ? "Stop it?" : server.processName)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isConfirmingStop ? .white : .secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(PressableButtonStyle())
            .help("Open \(server.url.absoluteString)")

            Button {
                if isConfirmingStop {
                    scanner.stop(server)
                } else {
                    withAnimation(.smooth(duration: 0.2)) { isConfirmingStop = true }
                    // Back out on its own if not confirmed.
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.smooth(duration: 0.2)) { isConfirmingStop = false }
                    }
                }
            } label: {
                Image(systemName: isConfirmingStop ? "stop.fill" : "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(isConfirmingStop ? .white : .white.opacity(0.5))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(isConfirmingStop ? .white.opacity(0.25) : .white.opacity(0.08)))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableButtonStyle())
            .help(isConfirmingStop ? "Click to stop \(server.processName) (pid \(server.pid))" : "Stop this server")
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isConfirmingStop ? Color.red.opacity(0.75) : .white.opacity(0.08))
        )
    }
}

private struct DevToolsRow: View {
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tools")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                if let feedback {
                    Text(feedback)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            HStack(spacing: 6) {
                tool("JSON", symbol: "curlybraces") {
                    show(DevUtilities.formatClipboardJSON() ? "JSON formatted" : "Clipboard isn't JSON")
                }
                tool("Pick color", symbol: "eyedropper") {
                    DevUtilities.pickColor { hex in
                        if let hex { show("Copied \(hex)") }
                    }
                }
            }
        }
    }

    private func tool(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: 62, height: 40)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08)))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func show(_ message: String) {
        withAnimation(.smooth(duration: 0.2)) { feedback = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.smooth(duration: 0.2)) { if feedback == message { feedback = nil } }
        }
    }
}
