import AppKit
import SwiftUI

/// Tracks what's playing in Spotify or Music and exposes playback controls.
///
/// Playback notifications from the apps give instant updates. A slow poll catches seeks and
/// anything else the notifications miss. Between reads, the playback position is interpolated
/// locally so the progress bar moves smoothly.
@Observable
final class MusicManager {
    private(set) var app: PlayerApp?
    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var isShuffling = false
    private(set) var artwork: NSImage?
    private(set) var accentColor: Color = .white

    // Interpolation anchor: position at `anchorDate`.
    private var anchorPosition: TimeInterval = 0
    private var anchorDate = Date()

    @ObservationIgnored var onTrackChange: ((Track?) -> Void)?

    @ObservationIgnored private var lastActiveApp: PlayerApp?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var ignoreUpdatesUntil = Date.distantPast
    @ObservationIgnored private var artworkTrackID: String?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        let distributed = DistributedNotificationCenter.default()
        for player in PlayerApp.allCases {
            let token = distributed.addObserver(forName: player.playbackNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.lastActiveApp = player
                    self?.refresh()
                }
            }
            observers.append((distributed, token))
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append((workspace, token))
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Current playback position, interpolated between reads.
    func elapsed(at date: Date = .now) -> TimeInterval {
        guard let track else { return 0 }
        let position = isPlaying ? anchorPosition + date.timeIntervalSince(anchorDate) : anchorPosition
        return min(max(position, 0), max(track.duration, 0))
    }

    // MARK: Controls

    func togglePlayPause() {
        guard let app else { return }
        resetAnchor(to: elapsed())
        withAnimation(.notchActivity) { isPlaying.toggle() }
        send("playpause", to: app)
    }

    func nextTrack() {
        guard let app else { return }
        send("next track", to: app)
    }

    func previousTrack() {
        guard let app else { return }
        send("previous track", to: app)
    }

    func toggleShuffle() {
        guard let app else { return }
        isShuffling.toggle()
        send("set \(app.shuffleProperty) to not \(app.shuffleProperty)", to: app)
    }

    func seek(to position: TimeInterval) {
        guard let app else { return }
        resetAnchor(to: position)
        send("set player position to \(position)", to: app)
    }

    /// Brings the current player (or Spotify, or Music) to the front.
    func openPlayer(_ preferred: PlayerApp? = nil) {
        let target = preferred ?? app ?? PlayerApp.allCases.first(where: \.isInstalled)
        guard let url = target?.applicationURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Refreshing

    func refresh() {
        guard !isRefreshing else { return }
        let running = PlayerApp.allCases.filter(\.isRunning)
        guard !running.isEmpty else {
            apply(nil)
            return
        }

        isRefreshing = true
        Task {
            var snapshots: [PlayerSnapshot] = []
            for player in running {
                let snapshot = await AppleScriptRunner.run(PlayerScripts.state(for: player)) {
                    PlayerScripts.parseState($0, app: player)
                }
                if let snapshot { snapshots.append(snapshot) }
            }
            isRefreshing = false
            apply(preferredSnapshot(from: snapshots))
        }
    }

    /// Prefers whatever is playing (favoring the app that last posted a notification),
    /// then a paused player.
    private func preferredSnapshot(from snapshots: [PlayerSnapshot]) -> PlayerSnapshot? {
        let playing = snapshots.filter(\.isPlaying)
        if let match = playing.first(where: { $0.app == lastActiveApp }) ?? playing.first {
            return match
        }
        return snapshots.first(where: { $0.app == lastActiveApp })
            ?? snapshots.first(where: { $0.app == app })
            ?? snapshots.first
    }

    private func apply(_ snapshot: PlayerSnapshot?) {
        // Skip reads that may predate a command we just sent, so the UI doesn't flicker back.
        guard Date() >= ignoreUpdatesUntil else { return }

        guard let snapshot else {
            guard track != nil else { return }
            withAnimation(.notchActivity) {
                track = nil
                app = nil
                isPlaying = false
                artwork = nil
            }
            artworkTrackID = nil
            onTrackChange?(nil)
            return
        }

        let trackChanged = snapshot.track.id != track?.id
        let predicted = elapsed()

        app = snapshot.app
        isShuffling = snapshot.isShuffling
        if track != snapshot.track { track = snapshot.track }

        if trackChanged || snapshot.isPlaying != isPlaying || abs(predicted - snapshot.position) > 1 {
            resetAnchor(to: snapshot.position)
        }
        if snapshot.isPlaying != isPlaying {
            withAnimation(.notchActivity) { isPlaying = snapshot.isPlaying }
        }
        if trackChanged {
            loadArtwork(for: snapshot)
            onTrackChange?(snapshot.track)
        }
    }

    private func resetAnchor(to position: TimeInterval) {
        anchorPosition = position
        anchorDate = Date()
    }

    private func send(_ command: String, to app: PlayerApp) {
        ignoreUpdatesUntil = Date().addingTimeInterval(0.5)
        AppleScriptRunner.send(PlayerScripts.command(command, for: app))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.refresh()
        }
    }

    // MARK: Artwork

    private func loadArtwork(for snapshot: PlayerSnapshot) {
        let trackID = snapshot.track.id
        artworkTrackID = trackID

        Task {
            var image: NSImage?
            switch snapshot.app {
            case .spotify:
                if let url = snapshot.track.artworkURL,
                   let (data, _) = try? await URLSession.shared.data(from: url) {
                    image = NSImage(data: data)
                }
            case .appleMusic:
                if let data = await AppleScriptRunner.run(PlayerScripts.appleMusicArtwork, transform: { $0.data }) {
                    image = NSImage(data: data)
                }
            }

            guard artworkTrackID == trackID else { return }
            withAnimation(.smooth(duration: 0.4)) {
                artwork = image
                accentColor = image?.notchAccentColor ?? .white
            }
        }
    }
}
