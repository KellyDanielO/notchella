import AppKit
import SwiftUI

/// A small persistent holding area for files dropped onto the notch.
@Observable
final class ShelfManager {
    private(set) var items: [URL] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "shelfItems"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = (defaults.stringArray(forKey: storageKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        let newItems = urls.filter { $0.isFileURL && !items.contains($0) }
        guard !newItems.isEmpty else { return }
        withAnimation(.smooth) { items.append(contentsOf: newItems) }
        save()
    }

    func remove(_ url: URL) {
        withAnimation(.smooth) { items.removeAll { $0 == url } }
        save()
    }

    func removeAll() {
        withAnimation(.smooth) { items.removeAll() }
        save()
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    private func save() {
        defaults.set(items.map(\.path), forKey: storageKey)
    }
}
