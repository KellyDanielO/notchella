import SwiftUI

struct LowBatteryClosedLeading: View {
    var body: some View {
        Image(systemName: "battery.25percent")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.red)
            .symbolEffect(.pulse, options: .repeat(3))
    }
}

struct LowBatteryClosedTrailing: View {
    @Environment(BatteryManager.self) private var battery

    var body: some View {
        Text("\(battery.level)%")
            .font(.system(size: 12, weight: .heavy).monospacedDigit())
            .foregroundStyle(.red)
    }
}

/// Drops down under the closed notch, like the iPhone's low battery alert.
struct LowBatteryBanner: View {
    @Environment(BatteryManager.self) private var battery

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Low Battery")
                    .font(.system(size: 13, weight: .bold))
                Text(battery.isLowPowerModeOn
                     ? "\(battery.level)% remaining · Low Power Mode is on"
                     : "\(battery.level)% battery remaining")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { battery.dismissLowBatteryWarning() }

            if !battery.isLowPowerModeOn {
                Button(action: battery.turnOnLowPowerMode) {
                    Text("Low Power Mode")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(.yellow))
                }
                .buttonStyle(.plain)
                .help("Turn on Low Power Mode while on battery")
            }
        }
    }
}
