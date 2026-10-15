import SwiftUI

/// How long the Mac has run since it last started up, as a pill in the open notch's header.
/// Hovering it slides out the day of the last restart.
struct UptimeBadge: View {
    @State private var isHovering = false

    var body: some View {
        // Uptime only changes by the minute, so there's no need to redraw more often.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let boot = SystemUptime.bootDate {
                let uptime = context.date.timeIntervalSince(boot)
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(Self.shortText(uptime))
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                    if isHovering {
                        Text("since \(boot.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize()
                            .transition(.blurFade.combined(with: .scale(scale: 0.6, anchor: .leading)))
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(.white.opacity(0.08)))
                .contentShape(Capsule())
                .onHover { hovering in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { isHovering = hovering }
                }
                .help(Self.helpText(uptime, boot: boot))
            }
        }
    }

    /// "42m" under an hour, "5h" under a day, then "12d".
    private static func shortText(_ uptime: TimeInterval) -> String {
        let minutes = Int(uptime / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }

    private static func helpText(_ uptime: TimeInterval, boot: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = uptime >= 24 * 60 * 60 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .full
        let running = formatter.string(from: uptime) ?? ""
        return "Running for \(running) without a restart or shut down. Last started \(boot.formatted(date: .abbreviated, time: .shortened))."
    }
}

enum SystemUptime {
    /// When the Mac last started up. Unlike `ProcessInfo.systemUptime`, this counts time asleep,
    /// so a laptop that's been closed overnight still shows the days since its last restart.
    static var bootDate: Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }
}
