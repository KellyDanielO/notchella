import Foundation

/// An affirmation you wrote.
nonisolated struct Affirmation: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var text: String
}
