import AppKit
import SwiftUI

/// Follows downloads into ~/Downloads using the progress that browsers publish for Finder
/// (the same progress that draws the bar on a downloading file's icon).
@Observable
final class DownloadMonitor {
    /// Overall progress of active downloads (0...1), or nil when nothing is downloading.
    private(set) var fraction: Double?
    private(set) var activeCount = 0
    private(set) var currentFileName: String?
    /// The download that just finished, shown briefly in the notch.
    private(set) var justFinished: URL?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var subscriber: Any?
    @ObservationIgnored private var tracked: [ObjectIdentifier: Tracked] = [:]
    @ObservationIgnored private var finishedTask: Task<Void, Never>?

    private final class Tracked {
        let progress: Progress
        /// Captured up front: the subscriber's copy of the progress can lose these by the time it ends.
        let fileURL: URL?
        var lastFraction: Double = 0
        var observation: NSKeyValueObservation?

        init(progress: Progress) {
            self.progress = progress
            fileURL = progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL
        }
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isShowingActivity: Bool {
        settings.downloadsActivity && (fraction != nil || justFinished != nil)
    }

    func start() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        subscriber = Progress.addSubscriber(forFileURL: downloads) { [weak self] progress in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.track(progress) }
            }
            return { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.untrack(progress) }
                }
            }
        }
    }

    func revealFinished() {
        guard let url = justFinished else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        dismissFinished()
    }

    func dismissFinished() {
        finishedTask?.cancel()
        withAnimation(.notchActivity) { justFinished = nil }
    }

    // MARK: Tracking

    private func track(_ progress: Progress) {
        let id = ObjectIdentifier(progress)
        guard tracked[id] == nil else { return }
        let entry = Tracked(progress: progress)
        entry.lastFraction = progress.fractionCompleted
        entry.observation = progress.observe(\.fractionCompleted) { [weak self, weak entry] progress, _ in
            let fraction = progress.fractionCompleted
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    entry?.lastFraction = max(entry?.lastFraction ?? 0, fraction)
                    self?.recompute()
                }
            }
        }
        tracked[id] = entry
        recompute()
    }

    private func untrack(_ progress: Progress) {
        guard let entry = tracked.removeValue(forKey: ObjectIdentifier(progress)) else { return }
        entry.observation?.invalidate()

        // Browsers unpublish when a download ends. Updates can trail behind the real progress,
        // so anything that got past 90% without being cancelled counts as finished.
        let fraction = max(entry.lastFraction, progress.fractionCompleted)
        if !progress.isCancelled, fraction >= 0.9 || progress.isFinished {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            announceFinished(entry.fileURL.map(Self.finalURL(for:)) ?? downloads)
        }
        recompute()
    }

    private func recompute() {
        let entries = Array(tracked.values)
        let newFraction = entries.isEmpty
            ? nil
            : entries.map { max($0.lastFraction, $0.progress.fractionCompleted) }.reduce(0, +) / Double(entries.count)
        withAnimation(.smooth(duration: 0.3)) {
            activeCount = entries.count
            fraction = newFraction
            currentFileName = entries.first?.fileURL.map { Self.finalURL(for: $0).lastPathComponent }
        }
    }

    private func announceFinished(_ url: URL) {
        guard settings.downloadsActivity else { return }
        finishedTask?.cancel()
        withAnimation(.notchActivity) { justFinished = url }
        finishedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismissFinished()
        }
    }

    /// Strips in-progress extensions (Chrome's `.crdownload`, Safari's `.download`, Firefox's `.part`).
    private nonisolated static func finalURL(for url: URL) -> URL {
        ["crdownload", "download", "part"].contains(url.pathExtension.lowercased()) ? url.deletingPathExtension() : url
    }
}
