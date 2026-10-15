import SwiftUI

extension View {
    /// A content panel inside the open notch: glass in the glass layout, a soft dark fill otherwise.
    func notchPanel(cornerRadius: CGFloat = 22) -> some View {
        modifier(NotchPanelBackground(cornerRadius: cornerRadius))
    }
}

private struct NotchPanelBackground: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(NotchViewModel.self) private var notch

    func body(content: Content) -> some View {
        if #available(macOS 26, *), notch.usesGlassLayout {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
        }
    }
}
