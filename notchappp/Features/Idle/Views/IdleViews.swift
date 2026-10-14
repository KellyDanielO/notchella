import SwiftUI

/// One of the notch's eyes: a soft, glowing pill with no pupil. The whole eye glides toward the
/// cursor, squashes to blink, rests as a flat dash late at night, goes tall when surprised, and
/// curves into a happy arc when the cursor comes close.
struct NotchEye: View {
    enum Side {
        case left
        case right
    }

    let side: Side

    @Environment(NotchViewModel.self) private var notch
    @Environment(IdleManager.self) private var idle

    /// Within this distance of the eye, the eyes turn happy.
    private static let noticeDistance: CGFloat = 150

    var body: some View {
        let look = lookVector()
        let isHappy = look.distance < Self.noticeDistance && idle.eyeMood != .surprised
        let mood = idle.eyeMood

        ZStack {
            if isHappy {
                HappyArc()
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .frame(width: 10, height: 6)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white)
                    .frame(width: eyeSize(mood).width, height: idle.isBlinking ? 1.6 : eyeSize(mood).height)
                    .offset(y: mood == .sleepy ? 3 : 0)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .shadow(color: .white.opacity(0.55), radius: 3)
        .offset(isHappy ? .zero : look.offset)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHappy)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: look.offset)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: mood)
        .frame(width: 18, height: 20)
    }

    private func eyeSize(_ mood: IdleManager.EyeMood) -> CGSize {
        switch mood {
        case .normal: CGSize(width: 7, height: 12)
        case .sleepy: CGSize(width: 9, height: 2.5)
        case .surprised: CGSize(width: 10, height: 15)
        }
    }

    /// How far to glide toward the cursor, and how far away the cursor is.
    private func lookVector() -> (offset: CGSize, distance: CGFloat) {
        let mouse = notch.mouseLocation
        let screen = notch.screenFrame
        let halfSpan = notch.notchSize.width / 2 + notch.wingWidth / 2
        let center = CGPoint(
            x: screen.midX + (side == .left ? -halfSpan : halfSpan),
            y: screen.maxY - notch.notchSize.height / 2
        )
        let dx = mouse.x - center.x
        let dy = center.y - mouse.y // Screen y grows upward; view y grows downward.
        let distance = max(hypot(dx, dy), 0.001)
        let reach = min(distance / 160, 1)
        let offset = CGSize(width: dx / distance * reach * 3, height: dy / distance * reach * 2.5)
        return (offset, distance)
    }
}

/// An upward arc, like a smiling eye (^).
private struct HappyArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6))
        return path
    }
}

/// The ambient affirmation drifting through the closed notch.
struct AmbientAffirmationView: View {
    @Environment(IdleManager.self) private var idle

    var body: some View {
        if let text = idle.ambientAffirmation {
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .id(text)
        }
    }
}

/// A slow, faint pulse of light around the closed notch, tinted by the last song played.
/// The glow comes from a copy of the notch's outline drawn behind it, so it hugs the real shape.
struct BreathingGlow: ViewModifier {
    let isActive: Bool
    let tint: Color
    let shape: NotchShape

    func body(content: Content) -> some View {
        content
            .background {
                if isActive {
                    PhaseAnimator([false, true]) { bright in
                        shape
                            .fill(.black)
                            .shadow(color: tint.opacity(bright ? 0.6 : 0.12), radius: bright ? 10 : 4, y: 2)
                    } animation: { _ in .easeInOut(duration: 2.8) }
                    .transition(.opacity)
                }
            }
    }
}
