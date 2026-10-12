import Foundation

/// Client for LRCLIB (https://lrclib.net), a free, open database of time-synced lyrics.
nonisolated struct LRCLibClient: Sendable {
    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private let baseURL = URL(string: "https://lrclib.net/api")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lyrics(for track: Track) async -> Lyrics {
        if let exact = await exactMatch(for: track), let lyrics = Self.lyrics(from: exact) {
            return lyrics
        }
        if let searched = await searchMatch(for: track), let lyrics = Self.lyrics(from: searched) {
            return lyrics
        }
        return .notFound
    }

    private func exactMatch(for track: Track) async -> Record? {
        var components = URLComponents(url: baseURL.appending(path: "get"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        return await fetch(Record.self, from: components.url)
    }

    /// Looser search with a cleaned-up title, choosing the closest match by duration.
    private func searchMatch(for track: Track) async -> Record? {
        var components = URLComponents(url: baseURL.appending(path: "search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: Self.cleanTitle(track.title)),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        guard let results = await fetch([Record].self, from: components.url), !results.isEmpty else { return nil }

        let closeInLength = results.filter { abs(($0.duration ?? 0) - track.duration) < 5 }
        let candidates = closeInLength.isEmpty ? results : closeInLength
        return candidates.first { $0.syncedLyrics?.isEmpty == false } ?? candidates.first
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL?) async -> T? {
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("notchappp/1.0 (personal notch app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func lyrics(from record: Record) -> Lyrics? {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = record.plainLyrics, !plain.isEmpty { return .plain(plain) }
        return nil
    }

    /// Strips suffixes like " - Remastered 2011" or " (feat. X)" that rarely match lyric databases.
    private static func cleanTitle(_ title: String) -> String {
        var cleaned = title
        if let dash = cleaned.range(of: " - ") { cleaned = String(cleaned[..<dash.lowerBound]) }
        cleaned = cleaned.replacing(/\s*[\(\[](feat|ft|with)\.?[^\)\]]*[\)\]]/.ignoresCase(), with: "")
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
