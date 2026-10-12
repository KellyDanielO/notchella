import SwiftUI

/// The spring curves that give the notch its feel. Tune them here in one place.
extension Animation {
    /// Near-critically damped: one clean expansion with no visible overshoot.
    static let notchOpen = Animation.spring(response: 0.4, dampingFraction: 0.88)
    static let notchClose = Animation.spring(response: 0.38, dampingFraction: 1)
    static let notchPeek = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let notchActivity = Animation.spring(response: 0.45, dampingFraction: 0.82)
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    /// Fades and un-blurs content in, which hides layout jumps while the notch resizes.
    static var blurFade: AnyTransition {
        .modifier(active: BlurModifier(radius: 8), identity: BlurModifier(radius: 0))
            .combined(with: .opacity)
    }
}
