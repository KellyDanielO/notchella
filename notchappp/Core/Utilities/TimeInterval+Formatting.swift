import Foundation

extension TimeInterval {
    /// Formats a playback time as `m:ss`.
    var playbackTimestamp: String {
        guard isFinite else { return "0:00" }
        let total = Int(self.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Elapsed or remaining time as `m:ss`, or `h:mm:ss` past an hour. Rounds up.
    var countdownText: String {
        let total = Int(self.rounded(.up))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
