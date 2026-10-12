import AppKit
import Observation
import Sparkle

/// Keeps Notchella up to date with Sparkle.
///
/// The feed URL and the public signing key live in `Config/Info.plist`. Sparkle checks once a day
/// and only installs updates signed with the matching private key from the developer's keychain.
@Observable
final class UpdateManager: NSObject, SPUStandardUserDriverDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController!

    /// Mirrors Sparkle's own preference so the Settings toggle stays in sync.
    var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    private(set) var lastChecked: Date?

    override init() {
        automaticallyChecks = true
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        lastChecked = controller.updater.lastUpdateCheckDate
    }

    func checkForUpdates() {
        // A menu bar app has no frontmost window, so bring the update dialog forward ourselves.
        NSApp.activate()
        controller.checkForUpdates(nil)
        lastChecked = .now
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Background (menu bar) apps should opt in so scheduled update alerts don't steal focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
