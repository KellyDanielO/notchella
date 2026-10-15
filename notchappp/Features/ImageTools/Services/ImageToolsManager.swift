import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Images dropped on the notch for editing, the recipe to apply, and the batch run.
///
/// Edits render straight away into a private preview folder, so the tray shows real results.
/// Nothing reaches Downloads until Save.
@Observable
final class ImageToolsManager {
    struct Item: Identifiable, Equatable {
        enum State: Equatable {
            case waiting
            case working
            /// Rendered into the preview folder, not saved yet.
            case ready(URL)
            /// Copied into Downloads.
            case saved(URL)
            case failed(String)
        }

        let id = UUID()
        let source: URL
        var original: NSImage?
        var result: NSImage?
        var state: State = .waiting

        /// What dragging the tile out hands over: the result once there is one.
        var fileURL: URL {
            switch state {
            case .ready(let url), .saved(let url): url
            default: source
            }
        }

        var hasResult: Bool {
            switch state {
            case .ready, .saved: true
            default: false
            }
        }
    }

    private(set) var items: [Item] = []
    private(set) var isRendering = false
    /// The item open in the large before/after preview.
    var previewedID: Item.ID?

    var removeBackground = true { didSet { recipeChanged() } }
    var size: ImageEditOptions.Size = .original { didSet { recipeChanged() } }
    var format: ImageEditOptions.Format = .same { didSet { recipeChanged() } }

    @ObservationIgnored private let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    @ObservationIgnored private let previewFolder = FileManager.default.temporaryDirectory.appending(path: "NotchellaPreviews")
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    /// Bumped whenever the recipe changes, so results rendered with an older recipe are dropped.
    @ObservationIgnored private var generation = 0

    /// Images render a few at a time: Vision is fast, but a big batch shouldn't pin every core.
    private static let parallelJobs = 3

    init() {
        // Previews from a previous session are never shown again.
        try? FileManager.default.removeItem(at: previewFolder)
    }

    // MARK: Counts

    private func count(where matches: (Item.State) -> Bool) -> Int {
        items.filter { matches($0.state) }.count
    }

    var readyCount: Int { count { if case .ready = $0 { true } else { false } } }
    var savedCount: Int { count { if case .saved = $0 { true } else { false } } }
    var failedCount: Int { count { if case .failed = $0 { true } else { false } } }

    /// Items that are rendered, saved, or failed: everything the current render is done with.
    var settledCount: Int { readyCount + savedCount + failedCount }

    /// 0…1 across the current render.
    var renderProgress: Double {
        items.isEmpty ? 0 : Double(settledCount) / Double(items.count)
    }

    // MARK: Editing the batch

    /// Adds the images among `urls` and returns whether there were any.
    @discardableResult
    func add(_ urls: [URL]) -> Bool {
        let images = urls.filter { url in
            url.isFileURL
                && (UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false)
                && !items.contains { $0.source == url }
        }
        guard !images.isEmpty else { return false }

        let newItems = images.map { Item(source: $0) }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { items.append(contentsOf: newItems) }
        for item in newItems {
            loadThumbnail(of: item.source, for: item.id, isResult: false)
        }
        render()
        return true
    }

    func remove(_ id: Item.ID) {
        if previewedID == id { previewedID = nil }
        withAnimation(.smooth(duration: 0.25)) { items.removeAll { $0.id == id } }
    }

    func clear() {
        renderTask?.cancel()
        generation += 1
        previewedID = nil
        withAnimation(.smooth(duration: 0.25)) { items.removeAll() }
        isRendering = false
        try? FileManager.default.removeItem(at: previewFolder)
    }

    func retryFailed() {
        for index in items.indices {
            if case .failed = items[index].state { items[index].state = .waiting }
        }
        render()
    }

    // MARK: Saving

    /// Copies every rendered result into Downloads under a readable, unique name.
    func save() {
        let options = currentOptions
        for index in items.indices {
            guard case .ready(let rendered) = items[index].state else { continue }
            let name = ImageProcessor.savedName(for: items[index].source, options: options, fileExtension: rendered.pathExtension)
            let destination = downloads.appending(path: name)
            do {
                try FileManager.default.copyItem(at: rendered, to: destination)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { items[index].state = .saved(destination) }
            } catch {
                items[index].state = .failed("Couldn't save to Downloads.")
            }
        }
    }

    func revealSaved() {
        let saved = items.compactMap { if case .saved(let url) = $0.state { url } else { nil } }
        if saved.isEmpty {
            NSWorkspace.shared.open(downloads)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(saved)
        }
    }

    // MARK: Rendering

    private var currentOptions: ImageEditOptions {
        ImageEditOptions(removeBackground: removeBackground, size: size, format: format, quality: 0.88)
    }

    /// A new recipe re-renders everything, including results already saved (the saved files stay).
    private func recipeChanged() {
        generation += 1
        for index in items.indices {
            items[index].state = .waiting
            items[index].result = nil
        }
        render()
    }

    /// Renders every waiting item. Called again whenever more work arrives; it picks up where it is.
    private func render() {
        renderTask?.cancel()
        let generation = generation
        let options = currentOptions
        let folder = previewFolder
        let jobs = items.filter { $0.state == .waiting || $0.state == .working }.map { ($0.id, $0.source) }
        guard !jobs.isEmpty else {
            isRendering = false
            return
        }

        for (id, _) in jobs { setState(.working, for: id) }
        withAnimation(.smooth) { isRendering = true }

        renderTask = Task {
            await withTaskGroup(of: (UUID, Result<URL, Error>).self) { group in
                var next = 0
                func enqueue() {
                    guard next < jobs.count, !Task.isCancelled else { return }
                    let (id, source) = jobs[next]
                    next += 1
                    group.addTask { await Self.render(id: id, source: source, options: options, folder: folder) }
                }
                for _ in 0..<Self.parallelJobs { enqueue() }
                for await (id, result) in group {
                    // A newer recipe took over; its own render will redo this item.
                    guard generation == self.generation else { continue }
                    switch result {
                    case .success(let url):
                        setState(.ready(url), for: id)
                        loadThumbnail(of: url, for: id, isResult: true)
                    case .failure(let error):
                        setState(.failed(error.localizedDescription), for: id)
                    }
                    enqueue()
                }
            }
            // A render that was replaced by a newer one leaves the flag to its successor.
            if generation == self.generation && !Task.isCancelled {
                withAnimation(.smooth) { isRendering = false }
            }
        }
    }

    private nonisolated static func render(id: UUID, source: URL, options: ImageEditOptions, folder: URL) async -> (UUID, Result<URL, Error>) {
        (id, Result { try ImageProcessor.process(source, options: options, into: folder) })
    }

    private func setState(_ state: Item.State, for id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { items[index].state = state }
    }

    private func loadThumbnail(of url: URL, for id: Item.ID, isResult: Bool) {
        Task {
            let cgImage = await Task.detached(priority: .utility) { ImageProcessor.thumbnail(of: url) }.value
            guard let cgImage, let index = items.firstIndex(where: { $0.id == id }) else { return }
            let image = NSImage(cgImage: cgImage, size: .zero)
            withAnimation(.smooth(duration: 0.3)) {
                if isResult {
                    items[index].result = image
                } else {
                    items[index].original = image
                }
            }
        }
    }
}
