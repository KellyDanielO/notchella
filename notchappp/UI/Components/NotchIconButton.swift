import SwiftUI

/// A borderless SF Symbol button with a hover highlight and a springy press.
struct NotchIconButton: View {
    let symbol: String
    var size: CGFloat = 15
    var tint: Color = .white
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 16, height: size + 16)
                .background(Circle().fill(.white.opacity(isHovered ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) { isHovered = hovering }
        }
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
