import SwiftUI

/// Fades content in after a short per-item delay, so sections of the open notch arrive
/// one after another without adding any movement on top of the notch's own expansion.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25).delay(0.08 + Double(index) * 0.05)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func staggeredAppear(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}
