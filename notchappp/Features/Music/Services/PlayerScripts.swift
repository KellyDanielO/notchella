import Foundation

/// AppleScript sources and result parsing for each supported player.
///
/// Each script checks `is running` first, so asking for state never launches the app.
nonisolated enum PlayerScripts {
    static func state(for app: PlayerApp) -> String {
        let artwork = app == .spotify ? "artwork url of t" : "\"\""
        let trackID = app == .spotify ? "id of t" : "persistent ID of t"
        return """
        if application id "\(app.bundleIdentifier)" is running then
            tell application id "\(app.bundleIdentifier)"
                try
                    if player state is stopped then return {"stopped"}
                    set t to current track
                    return {player state as string, \(trackID), name of t, artist of t, album of t, duration of t, player position, \(artwork), \(app.shuffleProperty)}
                on error
                    return {"stopped"}
                end try
            end tell
        end if
        return {"stopped"}
        """
    }

    static let appleMusicArtwork = """
    if application id "com.apple.Music" is running then
        tell application id "com.apple.Music"
            try
                return data of artwork 1 of current track
            end try
        end tell
    end if
    """

    static func command(_ command: String, for app: PlayerApp) -> String {
        """
        if application id "\(app.bundleIdentifier)" is running then
            tell application id "\(app.bundleIdentifier)" to \(command)
        end if
        """
    }

    static func parseState(_ descriptor: NSAppleEventDescriptor, app: PlayerApp) -> PlayerSnapshot? {
        guard descriptor.numberOfItems >= 9,
              let state = descriptor.atIndex(1)?.stringValue,
              state != "stopped",
              let title = descriptor.atIndex(3)?.stringValue
        else { return nil }

        var duration = descriptor.atIndex(6)?.doubleValue ?? 0
        if app == .spotify { duration /= 1000 } // Spotify reports milliseconds.

        let artworkString = descriptor.atIndex(8)?.stringValue ?? ""
        let artworkURL = URL(string: artworkString.replacingOccurrences(of: "http://", with: "https://"))

        let track = Track(
            id: descriptor.atIndex(2)?.stringValue ?? title,
            title: title,
            artist: descriptor.atIndex(4)?.stringValue ?? "",
            album: descriptor.atIndex(5)?.stringValue ?? "",
            duration: duration,
            artworkURL: artworkString.isEmpty ? nil : artworkURL
        )
        return PlayerSnapshot(
            app: app,
            track: track,
            isPlaying: state == "playing",
            position: descriptor.atIndex(7)?.doubleValue ?? 0,
            isShuffling: descriptor.atIndex(9)?.booleanValue ?? false
        )
    }
}
