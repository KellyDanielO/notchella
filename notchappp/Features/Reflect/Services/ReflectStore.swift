import SwiftUI

/// Your affirmations and a daily "grateful for" line, saved locally.
@Observable
final class ReflectStore {
    private(set) var affirmations: [Affirmation] = []
    private(set) var gratitude: [String: String] = [:]
    private(set) var currentID: UUID?

    @ObservationIgnored private let storageURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private struct Storage: Codable {
        var affirmations: [Affirmation]
        var gratitude: [String: String]

        private enum CodingKeys: String, CodingKey {
            case affirmations = "custom"
            case gratitude
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "notchappp")
            .appending(path: "Reflect")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storageURL = folder.appending(path: "reflect.json")
        load()
        showAffirmationOfTheDay()
    }

    // MARK: Affirmations

    var current: Affirmation? {
        affirmations.first { $0.id == currentID } ?? affirmations.first
    }

    /// 1-based position of the current affirmation, for the "3 of 7" counter.
    var currentPosition: Int {
        guard let current else { return 0 }
        return (affirmations.firstIndex { $0.id == current.id } ?? 0) + 1
    }

    /// A different affirmation each day, until you browse.
    func showAffirmationOfTheDay() {
        guard !affirmations.isEmpty else { return }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        currentID = affirmations[day % affirmations.count].id
    }

    func select(_ affirmation: Affirmation) { currentID = affirmation.id }
    func next() { step(by: 1) }
    func previous() { step(by: -1) }

    func shuffle() {
        if let pick = affirmations.filter({ $0.id != current?.id }).randomElement() {
            currentID = pick.id
        }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let affirmation = Affirmation(text: trimmed)
        affirmations.insert(affirmation, at: 0)
        currentID = affirmation.id
        scheduleSave()
    }

    func delete(_ affirmation: Affirmation) {
        if affirmation.id == current?.id { step(by: 1) }
        affirmations.removeAll { $0.id == affirmation.id }
        if affirmations.isEmpty { currentID = nil }
        scheduleSave()
    }

    func deleteAll() {
        affirmations.removeAll()
        currentID = nil
        scheduleSave()
    }

    private func step(by offset: Int) {
        guard let current, let index = affirmations.firstIndex(where: { $0.id == current.id }) else { return }
        currentID = affirmations[(index + offset + affirmations.count) % affirmations.count].id
    }

    // MARK: Gratitude

    var todaysGratitude: String { gratitude[Self.dayFormatter.string(from: .now)] ?? "" }

    func setTodaysGratitude(_ text: String) {
        let key = Self.dayFormatter.string(from: .now)
        gratitude[key] = text.isEmpty ? nil : text
        scheduleSave()
    }

    // MARK: Storage

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let storage = try? JSONDecoder().decode(Storage.self, from: data)
        else { return }
        affirmations = storage.affirmations
        gratitude = storage.gratitude
    }

    /// Typing updates on every keystroke, so writes are batched.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            if let data = try? JSONEncoder().encode(Storage(affirmations: affirmations, gratitude: gratitude)) {
                try? data.write(to: storageURL, options: .atomic)
            }
        }
    }
}
