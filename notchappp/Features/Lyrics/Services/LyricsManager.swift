import Foundation
import Observation

/// Loads and caches lyrics for the current track.
@Observable
final class LyricsManager {
    enum State: Equatable {
        case idle
        case loading
        case loaded(Lyrics)
    }

    private(set) var state: State = .idle

    /// Lines sung slightly early so the highlighted line lands right as it's sung.
    static let leadTime: TimeInterval = 0.3

    @ObservationIgnored private let client = LRCLibClient()
    @ObservationIgnored private var cache: [String: Lyrics] = [:]
    @ObservationIgnored private var currentTrackID: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    var hasSyncedLyrics: Bool {
        if case .loaded(.synced) = state { return true }
        return false
    }

    func load(for track: Track?) {
        guard let track else {
            task?.cancel()
            currentTrackID = nil
            state = .idle
            return
        }
        guard track.id != currentTrackID else { return }

        task?.cancel()
        currentTrackID = track.id

        if let cached = cache[track.id] {
            state = .loaded(cached)
            return
        }

        state = .loading
        task = Task { [client] in
            let lyrics = await client.lyrics(for: track)
            guard !Task.isCancelled, currentTrackID == track.id else { return }
            cache[track.id] = lyrics
            state = .loaded(lyrics)
        }
    }

    /// The synced line playing at `time`, or `nil` before the first line or without synced lyrics.
    func line(at time: TimeInterval) -> LyricLine? {
        guard case .loaded(.synced(let lines)) = state,
              let index = LRCParser.index(in: lines, at: time + Self.leadTime)
        else { return nil }
        return lines[index]
    }
}
