import SwiftUI

/// A circular battery gauge with the percentage inside.
struct BatteryRing: View {
    @Environment(BatteryManager.self) private var battery
    var size: CGFloat = 24

    private var tint: Color {
        if battery.isCharging || battery.isPluggedIn { return .green }
        // Yellow in Low Power Mode, like the iPhone's battery icon.
        if battery.isLowPowerModeOn { return .yellow }
        if battery.level <= 20 { return .red }
        return .white
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(battery.level) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.6), radius: battery.isCharging ? 3 : 0)
            if battery.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(tint)
            } else {
                Text("\(battery.level)")
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size, height: size)
        .animation(.smooth, value: battery.level)
        .help("Battery \(battery.level)%")
    }
}
