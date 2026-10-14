import SwiftUI

/// The open notch in the liquid glass design: pages hang below the ink bar as glass cards.
///
/// On open the cards start fused into one blob tucked under the bar, then drop down and pull
/// apart, so the glass visibly separates like liquid. Switching tabs morphs the cards into
/// each other.
@available(macOS 26, *)
struct GlassOpenNotchView: View {
    let namespace: Namespace.ID

    @Environment(NotchViewModel.self) private var notch
    @Environment(AppSettings.self) private var settings
    @Environment(MusicManager.self) private var music
    @Environment(AgentMonitor.self) private var agents
    @Environment(XcodeBuildMonitor.self) private var xcode
    @Environment(DownloadMonitor.self) private var downloads
    @Namespace private var glass
    @State private var isSettled = false

    /// Cards closer than this blend into one shape. Settled cards sit just beyond it.
    private static let blendDistance: CGFloat = 10
    private static let settledGap: CGFloat = 12
    private static let playerWidth: CGFloat = 352
    private static let beadHeight: CGFloat = 36

    private var gap: CGFloat { isSettled ? Self.settledGap : 0 }

    var body: some View {
        // Only Home sits in a GlassEffectContainer. With the container around every tab, swapping
        // pages inside it while keyboard navigation is on sent SwiftUI's key-view loop rebuild
        // (FocusNavigationSequence) into an endless loop and froze the app. Replacing the whole
        // container on a tab switch avoids it.
        Group {
            if notch.tab == .home {
                GlassEffectContainer(spacing: Self.blendDistance) { home }
            } else {
                pageCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scaleEffect(x: isSettled ? 1 : 0.7, y: isSettled ? 1 : 0.25, anchor: .top)
        .offset(y: isSettled ? 0 : -NotchViewModel.glassGap - 8)
        .overlay(alignment: .top) { OpenAlertBanner().padding(.top, 6) }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { isSettled = true }
        }
    }

    // MARK: Home

    private var showsLyrics: Bool {
        settings.lyricsEnabled && settings.lyricsPanelVisible && music.track != nil
    }

    private var home: some View {
        HStack(alignment: .top, spacing: gap) {
            MusicPlayerView(namespace: namespace)
                .settlingContent(isSettled)
                .padding(14)
                .frame(width: Self.playerWidth)
                .frame(maxHeight: .infinity)
                .glassEffect(playerGlass, in: .rect(cornerRadius: 26))
                .glassEffectID("primary", in: glass)

            VStack(spacing: gap) {
                ZStack {
                    if showsLyrics {
                        LyricsView()
                            .mask(Self.edgeFade)
                            .transition(.blurFade)
                    } else {
                        CalendarView()
                            .transition(.blurFade)
                    }
                }
                .settlingContent(isSettled, delay: 0.05)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Glass doesn't clip, and scrolling lyrics would spill past the card.
                .clipShape(.rect(cornerRadius: 26))
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .glassEffectID("secondary", in: glass)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showsLyrics)

                if let bead {
                    GlassBeadContent(kind: bead, style: .regular)
                        .settlingContent(isSettled, delay: 0.1)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: Self.beadHeight, maxHeight: Self.beadHeight)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .glassEffectID("bead", in: glass)
                        .contentShape(.capsule)
                        .onTapGesture { open(bead) }
                        .transition(.blurFade)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: bead)
        }
    }

    /// Scrolling lyrics fade out toward the card's top and bottom edges instead of being cut off.
    private static let edgeFade = LinearGradient(
        stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.2),
            .init(color: .black, location: 0.8),
            .init(color: .clear, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The player picks up the album's colour.
    private var playerGlass: Glass {
        music.track == nil ? .regular : .regular.tint(music.accentColor.opacity(0.35))
    }

    // MARK: Other tabs

    @ViewBuilder
    private var pageCard: some View {
        ZStack {
            switch notch.tab {
            case .home:
                EmptyView()
            case .reflect:
                ReflectView()
            case .dev:
                DevView()
            case .shelf:
                ShelfView()
            }
        }
        .id(notch.tab)
        .transition(.blurFade)
        .settlingContent(isSettled)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(.rect(cornerRadius: 26))
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .glassEffectID("page-\(notch.tab.rawValue)", in: glass)
    }

    // MARK: Bead

    /// The most pressing thing running besides music, shown as a capsule under the agenda.
    /// There's room for one: an agent waiting on you, a download, a build, then a working agent.
    private var bead: NotchViewModel.Activity? {
        if agents.sessionNeedingInput != nil { return .agent }
        if downloads.isShowingActivity { return .download }
        if xcode.isBuilding { return .build }
        if agents.isAnyWorking { return .agent }
        return nil
    }

    private func open(_ bead: NotchViewModel.Activity) {
        if bead == .download {
            if downloads.justFinished != nil && downloads.fraction == nil { downloads.revealFinished() }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { notch.tab = .dev }
        }
    }
}

private extension View {
    /// Card contents fade in a beat after the glass lands, so the split reads first.
    func settlingContent(_ isSettled: Bool, delay: Double = 0) -> some View {
        self
            .opacity(isSettled ? 1 : 0)
            .blur(radius: isSettled ? 0 : 6)
            .animation(.smooth(duration: 0.3).delay(isSettled ? 0.12 + delay : 0), value: isSettled)
    }
}
