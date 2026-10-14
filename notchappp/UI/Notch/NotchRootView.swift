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

    private var isGlassOpen: Bool { isOpen && notch.usesGlassLayout }

    private var notchBody: some View {
        VStack(spacing: 0) {
            ink
                // Glass slides out from underneath the ink.
                .zIndex(1)

            if #available(macOS 26, *) {
                if isGlassOpen {
                    GlassOpenNotchView(namespace: namespace)
                        .frame(width: notch.glassCardsSize.width, height: notch.glassCardsSize.height, alignment: .top)
                        .padding(.top, NotchViewModel.glassGap)
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)).animation(.easeOut(duration: 0.14))
                        ))
                }
            }
        }
        .animation(.notchActivity, value: notch.closedBeads)
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            return true
        } isTargeted: { targeted in
            notch.isDropTargeted = targeted
        }
    }

    /// The black shape over the camera housing. In the glass layout it only holds the header.
    private var ink: some View {
        let size = notch.inkSize
        let shape = NotchShape(topRadius: notch.topRadius, bottomRadius: notch.bottomRadius)

        return ZStack(alignment: .top) {
            if isGlassOpen {
                NotchHeaderView()
                    .frame(height: notch.notchSize.height)
                    .transition(.opacity.animation(.smooth(duration: 0.2)))
            } else if isOpen {
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
        .shadow(color: .black.opacity(isOpen && !isGlassOpen ? 0.6 : 0), radius: 18, y: 8)
        .overlay(alignment: .topTrailing) { satellites }
    }

    /// Circles beside the closed notch for other running activities. They start flush with the
    /// frame's trailing edge and shift right by their own width plus the gap. That edge includes
    /// the top flare, so the gap is measured from the notch body by taking off its radius.
    @ViewBuilder
    private var satellites: some View {
        if #available(macOS 26, *), !notch.closedBeads.isEmpty {
            let count = CGFloat(notch.closedBeads.count)
            let width = count * notch.satelliteDiameter + (count - 1) * NotchViewModel.satelliteGap
            NotchSatellitesView(activities: notch.closedBeads, diameter: notch.satelliteDiameter)
                .fixedSize()
                .padding(.top, 2)
                .contentShape(.rect)
                .onTapGesture { notch.open() }
                .offset(x: width + NotchViewModel.satelliteGap - notch.topRadius)
        }
    }
}
