import SwiftUI

/// Now playing: artwork, track info, progress and controls.
struct MusicPlayerView: View {
    let namespace: Namespace.ID

    @Environment(MusicManager.self) private var music
    @Environment(AppSettings.self) private var settings

    private static let artworkSize: CGFloat = 104

    var body: some View {
        Group {
            if let track = music.track {
                HStack(spacing: 14) {
                    artwork
                    VStack(alignment: .leading, spacing: 0) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        PlaybackProgressBar()
                        Spacer(minLength: 4)
                        controls
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                EmptyPlayerView()
            }
        }
    }

    /// Shrinks slightly on pause, like the Music app.
    private var artwork: some View {
        ArtworkView(image: music.artwork, size: Self.artworkSize, cornerRadius: 12)
            .matchedGeometryEffect(id: "artwork", in: namespace)
            .overlay(alignment: .bottomTrailing) { playerBadge }
            .scaleEffect(music.isPlaying ? 1 : 0.92)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: music.isPlaying)
            .onTapGesture { music.openPlayer() }
            .help("Open \(music.app?.displayName ?? "player")")
    }

    @ViewBuilder
    private var playerBadge: some View {
        if let url = music.app?.applicationURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 22, height: 22)
                .offset(x: 6, y: 6)
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            NotchIconButton(
                symbol: "shuffle",
                size: 11,
                tint: music.isShuffling ? music.accentColor : .white.opacity(0.5),
                action: music.toggleShuffle
            )
            Spacer(minLength: 0)
            NotchIconButton(symbol: "backward.fill", size: 14, action: music.previousTrack)
            Spacer(minLength: 0)
            PlayPauseButton()
            Spacer(minLength: 0)
            NotchIconButton(symbol: "forward.fill", size: 14, action: music.nextTrack)
            Spacer(minLength: 0)
            if settings.lyricsEnabled {
                NotchIconButton(
                    symbol: "quote.bubble.fill",
                    size: 11,
                    tint: settings.lyricsPanelVisible ? music.accentColor : .white.opacity(0.5)
                ) {
                    withAnimation(.smooth(duration: 0.3)) { settings.lyricsPanelVisible.toggle() }
                }
                .help("Lyrics")
            } else {
                NotchIconButton(symbol: "arrow.up.forward.app", size: 11, tint: .white.opacity(0.5)) {
                    music.openPlayer()
                }
            }
        }
    }
}

/// A solid white disc with a black glyph.
private struct PlayPauseButton: View {
    @Environment(MusicManager.self) private var music

    var body: some View {
        Button(action: music.togglePlayPause) {
            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private struct EmptyPlayerView: View {
    @Environment(MusicManager.self) private var music
    private static let artworkSize: CGFloat = 104

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(image: nil, size: Self.artworkSize, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 6) {
                Text("Silence is golden")
                    .font(.system(size: 15, weight: .bold))
                Text("Play something and it lands here.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(PlayerApp.allCases.filter(\.isInstalled), id: \.self) { player in
                        Button(player.displayName) { music.openPlayer(player) }
                            .buttonStyle(PressableButtonStyle())
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.12)))
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}
