import Foundation

/// A keyword rule for notification alerts.
///
/// `keywords` is comma-separated; each entry can be a word or a phrase ("call me").
/// `.any` fires when one entry appears, `.all` only when every entry appears (a word combination).
/// Matching is case- and accent-insensitive, on whole words.
nonisolated struct AlertRule: Identifiable, Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case any
        case all

        var label: String {
            switch self {
            case .any: "Any word"
            case .all: "All words"
            }
        }
    }

    var id = UUID()
    var keywords: String
    var mode: Mode = .any
    var isEnabled = true

    var terms: [String] {
        keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The terms found in `text` if the rule matches, otherwise `nil`.
    func matches(in text: String) -> [String]? {
        let terms = terms
        guard isEnabled, !terms.isEmpty else { return nil }
        let found = terms.filter { Self.contains(text, term: $0) }
        switch mode {
        case .any: return found.isEmpty ? nil : found
        case .all: return found.count == terms.count ? found : nil
        }
    }

    private static func contains(_ text: String, term: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: term) + "(?![\\p{L}\\p{N}])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive, .diacriticInsensitive]) != nil
    }
}

/// A notification that matched a rule, shown in the notch.
nonisolated struct NotchAlert: Identifiable, Equatable, Sendable {
    let id = UUID()
    let appName: String?
    let title: String
    let body: String
    let matchedTerms: [String]
}
