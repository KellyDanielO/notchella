import AppKit
import SwiftUI

nonisolated struct XcodeBuildResult: Equatable, Sendable {
    enum Status: Sendable {
        case succeeded
        case failed
        case cancelled
    }

    let scheme: String
    let status: Status
    let errors: Int
    let warnings: Int
    let duration: TimeInterval
    let finishedAt: Date
}

/// Follows Xcode (and `xcodebuild`) builds without any setup.
///
/// - Building: Xcode's build service (`SWBBuildService`, formerly `XCBBuildService`) has compiler
///   processes running under it. Idle, it has none.
/// - Result: every build adds an entry to `DerivedData/<project>/Logs/Build/LogStoreManifest.plist`
///   with its scheme, status, and error and warning counts.
@Observable
final class XcodeBuildMonitor {
    private(set) var isBuilding = false
    private(set) var buildingSince: Date?
    private(set) var buildingProject: String?
    private(set) var lastResult: XcodeBuildResult?
    /// The result that just came in, shown in the closed notch for a few seconds.
    private(set) var freshResult: XcodeBuildResult?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let queue = DispatchQueue(label: "com.kellydaniel.notchappp.xcode", qos: .utility)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var busySince: Date?
    @ObservationIgnored private var manifestDates: [URL: Date] = [:]
    @ObservationIgnored private var lastSeenFinish: Date?
    @ObservationIgnored private var freshTask: Task<Void, Never>?

    private nonisolated static let serviceNames: Set<String> = ["SWBBuildService", "XCBBuildService"]
    /// Builds shorter than this aren't announced as "Building", which keeps quick
    /// background work (like Xcode preparing the editor) from flickering in the notch.
    private static let buildingDebounce: TimeInterval = 1.5

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        // Only the baseline: builds that finished before launch aren't announced.
        checkManifests(announce: false)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard settings.xcodeBuildStatusEnabled else {
            if isBuilding { setBuilding(false, project: nil) }
            return
        }
        tick += 1
        let isXcodeAround = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode").isEmpty
        guard isXcodeAround || isBuilding || tick % 5 == 0 else { return }

        queue.async { [weak self] in
            let state = Self.scanBuildService()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(state) }
            }
        }
    }

    private func apply(_ state: (busy: Bool, project: String?)) {
        let now = Date()
        if state.busy {
            if busySince == nil { busySince = now }
            if !isBuilding, let busySince, now.timeIntervalSince(busySince) >= Self.buildingDebounce {
                setBuilding(true, project: state.project, since: busySince)
            } else if isBuilding, let project = state.project, project != buildingProject {
                buildingProject = project
            }
        } else {
            busySince = nil
            if isBuilding { setBuilding(false, project: nil) }
        }

        // Results land when a build ends, so check often while building and right after.
        if isBuilding || !state.busy || tick % 3 == 0 {
            checkManifests(announce: true)
        }
    }

    private func setBuilding(_ building: Bool, project: String?, since: Date? = nil) {
        withAnimation(.notchActivity) {
            isBuilding = building
            buildingProject = project
            buildingSince = building ? (since ?? Date()) : nil
        }
    }

    // MARK: Results

    private func checkManifests(announce shouldAnnounce: Bool) {
        var newest: XcodeBuildResult?
        for manifest in Self.manifestURLs() {
            let modified = (try? manifest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard manifestDates[manifest] != modified else { continue }
            manifestDates[manifest] = modified
            if let result = Self.latestResult(in: manifest), result.finishedAt > (newest?.finishedAt ?? .distantPast) {
                newest = result
            }
        }

        guard let newest, newest.finishedAt > (lastSeenFinish ?? .distantPast) else { return }
        lastSeenFinish = newest.finishedAt
        withAnimation(.smooth) { lastResult = newest }
        if shouldAnnounce { announce(newest) }
    }

    private func announce(_ result: XcodeBuildResult) {
        if isBuilding { setBuilding(false, project: nil) }
        busySince = nil

        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if result.status == .failed && settings.buildFailureSound {
            NSSound(named: "Basso")?.play()
        }

        freshTask?.cancel()
        withAnimation(.notchActivity) { freshResult = result }
        freshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(result.status == .failed ? 8 : 5))
            guard !Task.isCancelled else { return }
            withAnimation(.notchActivity) { self?.freshResult = nil }
        }
    }

    // MARK: Scanning (background queue)

    private nonisolated static func scanBuildService() -> (busy: Bool, project: String?) {
        let entries = ProcessTable.snapshot()
        let services = entries.filter { serviceNames.contains($0.name) }
        guard !services.isEmpty else { return (false, nil) }

        let children = ProcessTable.childrenMap(entries)
        let names = Dictionary(entries.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
        let workers = services.flatMap { ProcessTable.descendants(of: $0.pid, in: children) }
        guard !workers.isEmpty else { return (false, nil) }

        // The Swift compiler's arguments name the module being built.
        let project = workers
            .lazy
            .filter { names[$0] == "swift-frontend" }
            .compactMap { pid -> String? in
                let arguments = ProcessTable.arguments(of: pid)
                guard let index = arguments.firstIndex(of: "-module-name"), index + 1 < arguments.count else { return nil }
                return arguments[index + 1]
            }
            .first
        return (true, project)
    }

    // MARK: DerivedData

    /// Xcode's DerivedData folder (honoring a custom location set in Xcode), plus an optional
    /// extra root, e.g. for command-line builds that pass `-derivedDataPath`.
    private static func derivedDataRoots() -> [URL] {
        var roots = [FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Developer/Xcode/DerivedData")]
        if let custom = CFPreferencesCopyAppValue("IDECustomDerivedDataLocation" as CFString, "com.apple.dt.Xcode" as CFString) as? String {
            roots.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath))
        }
        if let extra = UserDefaults.standard.string(forKey: "NotchExtraDerivedDataRoot") {
            roots.append(URL(fileURLWithPath: (extra as NSString).expandingTildeInPath))
        }
        return roots
    }

    private static func manifestURLs() -> [URL] {
        derivedDataRoots().flatMap { root -> [URL] in
            let direct = root.appending(path: "Logs/Build/LogStoreManifest.plist")
            let projects = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            return ([direct] + projects.map { $0.appending(path: "Logs/Build/LogStoreManifest.plist") })
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private nonisolated static func latestResult(in manifest: URL) -> XcodeBuildResult? {
        guard let data = try? Data(contentsOf: manifest),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let logs = plist["logs"] as? [String: [String: Any]]
        else { return nil }

        let builds = logs.values.filter { ($0["title"] as? String)?.hasPrefix("Build") ?? false }
        guard let entry = builds.max(by: { ($0["timeStoppedRecording"] as? Double ?? 0) < ($1["timeStoppedRecording"] as? Double ?? 0) }),
              let stopped = entry["timeStoppedRecording"] as? Double
        else { return nil }

        let started = entry["timeStartedRecording"] as? Double ?? stopped
        let observable = entry["primaryObservable"] as? [String: Any] ?? [:]
        let errors = observable["totalNumberOfErrors"] as? Int ?? 0
        let warnings = observable["totalNumberOfWarnings"] as? Int ?? 0
        let code = observable["highLevelStatus"] as? String ?? "S"

        let status: XcodeBuildResult.Status = if errors > 0 || code == "E" {
            .failed
        } else if code == "C" {
            .cancelled
        } else {
            .succeeded
        }

        let scheme = entry["schemeIdentifier-schemeName"] as? String
            ?? (entry["title"] as? String)?.replacingOccurrences(of: "Build ", with: "")
            ?? "Build"
        return XcodeBuildResult(
            scheme: scheme,
            status: status,
            errors: errors,
            warnings: warnings,
            duration: stopped - started,
            finishedAt: Date(timeIntervalSinceReferenceDate: stopped)
        )
    }
}
