import SwiftUI

/// The expanded notch: a header row beside the camera housing, then the selected page of cards.
struct OpenNotchView: View {
    let namespace: Namespace.ID

    @Environment(NotchViewModel.self) private var notch

    var body: some View {
        VStack(spacing: 0) {
            NotchHeaderView()
                .frame(height: notch.notchSize.height)
                // Always above page content, so nothing on a page can block the tabs.
                .zIndex(1)

            ZStack {
                switch notch.tab {
                case .home:
                    HomeView(namespace: namespace)
                        .transition(.blurFade.combined(with: .offset(x: -24)))
                case .reflect:
                    ReflectView()
                        .transition(.blurFade)
                case .dev:
                    DevView()
                        .transition(.blurFade)
                case .shelf:
                    ShelfView()
                        .staggeredAppear(0)
                        .transition(.blurFade.combined(with: .offset(x: 24)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: notch.tab)
            .overlay(alignment: .top) { OpenAlertBanner() }
        }
    }
}

/// While the notch is open, alerts slide in over the top of the content.
struct OpenAlertBanner: View {
    @Environment(AlertManager.self) private var alerts

    var body: some View {
        ZStack {
            if alerts.currentAlert != nil {
                HStack(spacing: 10) {
                    AlertBellIcon()
                    AlertBannerContent()
                    AlertKeywordChip()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.12))
                        .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
                )
                .padding(.horizontal, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.notchOpen, value: alerts.currentAlert?.id)
    }
}

struct NotchHeaderView: View {
    @Environment(NotchViewModel.self) private var notch
    @Environment(BatteryManager.self) private var battery
    @Environment(HUDManager.self) private var hud
    @Environment(KeepAwakeManager.self) private var keepAwake

    var body: some View {
        HStack(spacing: 0) {
            TabSwitcher()
                .frame(maxWidth: .infinity, alignment: .leading)

            // Keep everything clear of the camera housing.
            Color.clear.frame(width: notch.notchSize.width)

            ZStack(alignment: .trailing) {
                if hud.visibleKind != nil {
                    HUDInlineIndicator()
                        .transition(.blurFade)
                } else {
                    HStack(spacing: 6) {
                        if keepAwake.isHoldingAssertion {
                            Image(systemName: "cup.and.heat.waves.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.yellow)
                                .help("Keeping your Mac awake")
                                .transition(.scale.combined(with: .opacity))
                        }
                        HeadphonesHeaderBadge()
                        if battery.hasBattery {
                            BatteryRing(size: 22)
                        }
                        NotchIconButton(symbol: "gearshape.fill", size: 11, tint: .white.opacity(0.6), action: notch.openSettings)
                    }
                    .transition(.blurFade)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(.smooth(duration: 0.25), value: hud.visibleKind)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }
}

/// Icon pills; the selected one stretches to reveal its label.
private struct TabSwitcher: View {
    @Environment(NotchViewModel.self) private var notch
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchViewModel.Tab.allCases) { tab in
                let isSelected = notch.tab == tab
                HStack(spacing: 5) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .bold))
                    if isSelected {
                        Text(tab.title)
                            .font(.system(size: 11, weight: .bold))
                            .fixedSize()
                            .transition(.blurFade.combined(with: .scale(scale: 0.6, anchor: .leading)))
                    }
                }
                .foregroundStyle(isSelected ? .black : .white.opacity(0.55))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.white)
                            .matchedGeometryEffect(id: "tab", in: selection)
                    }
                }
                .contentShape(Capsule())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { notch.tab = tab }
                }
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}

private struct HomeView: View {
    let namespace: Namespace.ID

    @Environment(AppSettings.self) private var settings
    @Environment(MusicManager.self) private var music

    private var showsLyrics: Bool {
        settings.lyricsEnabled && settings.lyricsPanelVisible && music.track != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            MusicPlayerView(namespace: namespace)
                .frame(width: 336)
                .padding(.trailing, 16)
                .staggeredAppear(0)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 10)

            ZStack {
                if showsLyrics {
                    LyricsView()
                        .transition(.blurFade.combined(with: .scale(scale: 0.95)))
                } else {
                    CalendarView()
                        .transition(.blurFade.combined(with: .scale(scale: 0.95)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, 16)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showsLyrics)
            .staggeredAppear(1)
        }
    }
}
