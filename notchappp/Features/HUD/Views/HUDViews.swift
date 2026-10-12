import SwiftUI

/// Icon for the visible HUD. The volume icon's waves fill in with the level.
struct HUDIcon: View {
    @Environment(HUDManager.self) private var hud
    var size: CGFloat = 13

    var body: some View {
        Group {
            switch hud.visibleKind {
            case .volume:
                if hud.isMuted || hud.volume == 0 {
                    Image(systemName: "speaker.slash.fill")
                } else {
                    Image(systemName: "speaker.wave.3.fill", variableValue: Double(hud.volume))
                }
            case .brightness:
                Image(systemName: hud.brightness < 0.5 ? "sun.min.fill" : "sun.max.fill")
                    .foregroundStyle(.yellow)
            case nil:
                EmptyView()
            }
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(.white)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: size + 10)
    }
}

/// A 16-segment meter, one segment per key press, the way macOS steps the level.
/// The leading segment fills partially for fine (Option+Shift) steps.
struct HUDSegmentMeter: View {
    @Environment(HUDManager.self) private var hud
    var segmentHeight: CGFloat = 11

    private static let segments = 16

    var body: some View {
        let filled = CGFloat(hud.level) * CGFloat(Self.segments)
        let tint: Color = hud.visibleKind == .brightness ? .yellow : .white

        HStack(spacing: 1.6) {
            ForEach(0..<Self.segments, id: \.self) { index in
                let amount = min(max(filled - CGFloat(index), 0), 1)
                Capsule()
                    .fill(.white.opacity(0.16))
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(tint)
                            .frame(height: segmentHeight * amount)
                    }
                    .frame(width: 3, height: segmentHeight)
                    .shadow(color: tint.opacity(amount > 0 ? 0.5 : 0), radius: 2)
            }
        }
        .opacity(hud.visibleKind == .volume && hud.isMuted ? 0.4 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hud.level)
    }
}

/// Compact HUD used in the header while the notch is open.
struct HUDInlineIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            HUDIcon(size: 12)
            HUDSegmentMeter(segmentHeight: 9)
        }
    }
}
