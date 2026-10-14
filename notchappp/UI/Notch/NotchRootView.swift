import SwiftUI

/// Fills the transparent panel and draws the notch at the top center.
struct NotchRootView: View {
    @Environment(NotchViewModel.self) private var notch
    @Environment(ShelfManager.self) private var shelf
    @Environment(MusicManager.self) private var music
    @Environment(AppSettings.self) private var settings
    @Namespace private var namespace

    var body: some View {
        notchBody
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    private var isOpen: Bool { notch.status == .open }

    private var notchBody: some View {
        let size = notch.currentSize
        let shape = NotchShape(topRadius: notch.topRadius, bottomRadius: notch.bottomRadius)

        return ZStack(alignment: .top) {
            if isOpen {
                OpenNotchView(namespace: namespace)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.smooth(duration: 0.2)),
                            removal: .opacity.animation(.easeOut(duration: 0.12))
                        )
                    )
            } else {
                ClosedNotchView(namespace: namespace)
                    .transition(.blurFade.animation(.smooth(duration: 0.25)))
            }
        }
        .padding(.horizontal, notch.topRadius)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black)
        .clipShape(shape)
        .modifier(BreathingGlow(
            isActive: settings.idleBreathingGlow && !isOpen && (notch.activity == .none || notch.activity == .idle),
            tint: music.artwork == nil ? .white : music.accentColor,
            shape: shape
        ))
        .contentShape(shape)
        .shadow(color: .black.opacity(isOpen ? 0.6 : 0), radius: 18, y: 8)
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            return true
        } isTargeted: { targeted in
            notch.isDropTargeted = targeted
        }
    }
}
