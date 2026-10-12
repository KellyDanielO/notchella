import Foundation

nonisolated struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let time: TimeInterval
    let text: String
}

nonisolated enum Lyrics: Equatable, Sendable {
    case synced([LyricLine])
    case plain(String)
    case instrumental
    case notFound
}

nonisolated enum LRCParser {
    private static let timestamp = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/

    /// Parses `.lrc` text. A line may carry several timestamps, e.g. `[00:12.00][01:15.00]text`.
    static func parse(_ text: String) -> [LyricLine] {
        var entries: [(TimeInterval, String)] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = Substring(rawLine)
            var times: [TimeInterval] = []
            while let match = line.prefixMatch(of: timestamp) {
                let minutes = Double(match.1) ?? 0
                let seconds = Double(match.2.replacingOccurrences(of: ":", with: ".")) ?? 0
                times.append(minutes * 60 + seconds)
                line = line[match.range.upperBound...]
            }
            let lyric = line.trimmingCharacters(in: .whitespaces)
            entries += times.map { ($0, lyric) }
        }

        return entries
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    /// Index of the line being sung at `time`, if any.
    static func index(in lines: [LyricLine], at time: TimeInterval) -> Int? {
        var low = 0, high = lines.count - 1, result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
