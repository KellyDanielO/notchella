import SwiftUI

private extension XcodeBuildResult {
    var symbol: String {
        switch status {
        case .succeeded: warnings > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "stop.circle.fill"
        }
    }

    var tint: Color {
        switch status {
        case .succeeded: warnings > 0 ? .yellow : .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }

    /// Short text for the closed notch.
    var compactSummary: String {
        switch status {
        case .failed: errors == 1 ? "1 error" : "\(errors) errors"
        case .cancelled: "Stopped"
        case .succeeded: warnings > 0 ? "\(warnings) warn" : "Built " + duration.buildDuration
        }
    }

    var summary: String {
        switch status {
        case .failed:
            "Failed with \(errors == 1 ? "1 error" : "\(errors) errors")"
        case .cancelled:
            "Cancelled"
        case .succeeded:
            warnings > 0
                ? "Succeeded with \(warnings == 1 ? "1 warning" : "\(warnings) warnings") in \(duration.buildDuration)"
                : "Succeeded in \(duration.buildDuration)"
        }
    }
}

private extension TimeInterval {
    var buildDuration: String {
        self < 60 ? "\(Int(self.rounded()))s" : "\(Int(self) / 60)m \(Int(self) % 60)s"
    }
}

/// The hammer while building, or the result icon right after.
struct XcodeClosedLeading: View {
    @Environment(XcodeBuildMonitor.self) private var xcode

    var body: some View {
        if let result = xcode.freshResult {
            Image(systemName: result.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(result.tint)
                .symbolEffect(.bounce, options: .nonRepeating, value: result.finishedAt)
                .help("\(result.scheme): \(result.summary)")
        } else {
            Image(systemName: "hammer.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1))
                .symbolEffect(.wiggle, options: .repeat(.continuous))
                .help("Building \(xcode.buildingProject ?? "")")
        }
    }
}

/// Elapsed build time, or the result summary.
struct XcodeClosedTrailing: View {
    @Environment(XcodeBuildMonitor.self) private var xcode

    var body: some View {
        Group {
            if let result = xcode.freshResult {
                Text(result.compactSummary)
                    .foregroundStyle(result.tint)
            } else if let since = xcode.buildingSince {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date.timeIntervalSince(since).countdownText)
                        .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1))
                }
            }
        }
        .font(.system(size: 12, weight: .bold).monospacedDigit())
        .lineLimit(1)
        // The compact wing fits "12:34"; a build past an hour shrinks a little instead of cutting off.
        .minimumScaleFactor(0.75)
    }
}

/// A row in the Dev tab: live build progress or the last result.
struct XcodeBuildRow: View {
    @Environment(XcodeBuildMonitor.self) private var xcode

    var body: some View {
        if xcode.isBuilding || xcode.lastResult != nil {
            HStack(spacing: 8) {
                Image(systemName: xcode.isBuilding ? "hammer.fill" : (xcode.lastResult?.symbol ?? "hammer.fill"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(xcode.isBuilding ? Color(red: 0.35, green: 0.65, blue: 1) : (xcode.lastResult?.tint ?? .secondary))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(xcode.isBuilding ? (xcode.buildingProject ?? "Xcode") : (xcode.lastResult?.scheme ?? "Xcode"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Group {
                        if xcode.isBuilding {
                            Text("Building…")
                        } else if let result = xcode.lastResult {
                            Text("\(result.summary) · \(result.finishedAt, format: .relative(presentation: .named))")
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let since = xcode.buildingSince {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(context.date.timeIntervalSince(since).countdownText)
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.06)))
        }
    }
}
