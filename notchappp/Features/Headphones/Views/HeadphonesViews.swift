import SwiftUI

private func batteryTint(_ level: Int?) -> Color {
    guard let level else { return .white }
    return level <= HeadphonesManager.lowBatteryLevel ? .red : (level <= 30 ? .orange : .green)
}

/// Left wing: the device's icon, bouncing in on connect.
struct HeadphonesClosedLeading: View {
    @Environment(HeadphonesManager.self) private var headphones

    var body: some View {
        if let device = headphones.device {
            Image(systemName: device.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(headphones.isShowingLowBattery ? .red : .white)
                .symbolEffect(.bounce, options: .nonRepeating, value: headphones.isShowingConnection)
                .help(device.name)
        }
    }
}

/// Right wing: one battery level, or left and right for earbuds.
struct HeadphonesClosedTrailing: View {
    @Environment(HeadphonesManager.self) private var headphones

    var body: some View {
        if let device = headphones.device {
            HStack(spacing: 6) {
                if device.hasSeparateBuds {
                    level("L", device.left)
                    level("R", device.right)
                } else if let main = device.main {
                    level(nil, main)
                } else {
                    Text("Connected")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .lineLimit(1)
        }
    }

    private func level(_ label: String?, _ value: Int?) -> some View {
        HStack(spacing: 2) {
            if let label {
                Text(label)
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(value.map { "\($0)%" } ?? "–")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(batteryTint(value))
                .contentTransition(.numericText())
        }
    }
}

/// Compact badge for the open notch's header while headphones are connected.
struct HeadphonesHeaderBadge: View {
    @Environment(HeadphonesManager.self) private var headphones

    var body: some View {
        if let device = headphones.device {
            HStack(spacing: 4) {
                Image(systemName: device.symbol)
                    .font(.system(size: 11, weight: .semibold))
                if let lowest = device.lowestLevel {
                    Text("\(lowest)%")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(batteryTint(lowest))
                }
            }
            .foregroundStyle(.white.opacity(0.8))
            .help(helpText(for: device))
        }
    }

    private func helpText(for device: HeadphoneDevice) -> String {
        var parts = [device.name]
        if let left = device.left { parts.append("Left \(left)%") }
        if let right = device.right { parts.append("Right \(right)%") }
        if let caseLevel = device.caseLevel { parts.append("Case \(caseLevel)%") }
        if let main = device.main, !device.hasSeparateBuds { parts.append("\(main)%") }
        return parts.joined(separator: " · ")
    }
}
