import AppKit

/// A media app the notch can read from and control.
nonisolated enum PlayerApp: String, CaseIterable, Sendable {
    case spotify = "com.spotify.client"
    case appleMusic = "com.apple.Music"

    var bundleIdentifier: String { rawValue }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Music"
        }
    }

    /// Distributed notification the app posts whenever playback changes.
    var playbackNotification: Notification.Name {
        switch self {
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .appleMusic: Notification.Name("com.apple.Music.playerInfo")
        }
    }

    var shuffleProperty: String {
        switch self {
        case .spotify: "shuffling"
        case .appleMusic: "shuffle enabled"
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    var isInstalled: Bool { applicationURL != nil }
}

nonisolated struct Track: Equatable, Sendable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkURL: URL?
}

/// A single read of a player's state.
nonisolated struct PlayerSnapshot: Sendable {
    var app: PlayerApp
    var track: Track
    var isPlaying: Bool
    var position: TimeInterval
    var isShuffling: Bool
}
