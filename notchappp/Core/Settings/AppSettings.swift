import Foundation
import Observation

/// User preferences, persisted to `UserDefaults` and observable from both views and services.
@Observable
final class AppSettings {
    private enum Key {
        static let openOnHover = "openOnHover"
        static let hoverDelay = "hoverDelay"
        static let hapticsEnabled = "hapticsEnabled"
        static let showMusicActivity = "showMusicActivity"
        static let showChargingActivity = "showChargingActivity"
        static let lyricsEnabled = "lyricsEnabled"
        static let lyricsUnderNotch = "lyricsUnderNotch"
        static let lyricsPanelVisible = "lyricsPanelVisible"
        static let replaceSystemHUD = "replaceSystemHUD"
        static let notificationAlertsEnabled = "notificationAlertsEnabled"
        static let alertSoundEnabled = "alertSoundEnabled"
        static let keepAwakeMode = "keepAwakeMode"
        static let keepDisplayAwake = "keepDisplayAwake"
        static let agentFinishAlerts = "agentFinishAlerts"
        static let fullChargeAlert = "fullChargeAlert"
        static let fullChargeTarget = "fullChargeTarget"
        static let xcodeBuildStatusEnabled = "xcodeBuildStatusEnabled"
        static let buildFailureSound = "buildFailureSound"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Key.openOnHover) } }
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) } }
    var showMusicActivity: Bool { didSet { defaults.set(showMusicActivity, forKey: Key.showMusicActivity) } }
    var showChargingActivity: Bool { didSet { defaults.set(showChargingActivity, forKey: Key.showChargingActivity) } }
    var lyricsEnabled: Bool { didSet { defaults.set(lyricsEnabled, forKey: Key.lyricsEnabled) } }
    var lyricsUnderNotch: Bool { didSet { defaults.set(lyricsUnderNotch, forKey: Key.lyricsUnderNotch) } }
    var lyricsPanelVisible: Bool { didSet { defaults.set(lyricsPanelVisible, forKey: Key.lyricsPanelVisible) } }
    var replaceSystemHUD: Bool { didSet { defaults.set(replaceSystemHUD, forKey: Key.replaceSystemHUD) } }
    var notificationAlertsEnabled: Bool { didSet { defaults.set(notificationAlertsEnabled, forKey: Key.notificationAlertsEnabled) } }
    var alertSoundEnabled: Bool { didSet { defaults.set(alertSoundEnabled, forKey: Key.alertSoundEnabled) } }
    var keepAwakeMode: KeepAwakeManager.Mode { didSet { defaults.set(keepAwakeMode.rawValue, forKey: Key.keepAwakeMode) } }
    var keepDisplayAwake: Bool { didSet { defaults.set(keepDisplayAwake, forKey: Key.keepDisplayAwake) } }
    var agentFinishAlerts: Bool { didSet { defaults.set(agentFinishAlerts, forKey: Key.agentFinishAlerts) } }
    var fullChargeAlert: Bool { didSet { defaults.set(fullChargeAlert, forKey: Key.fullChargeAlert) } }
    var fullChargeTarget: Int { didSet { defaults.set(fullChargeTarget, forKey: Key.fullChargeTarget) } }
    var xcodeBuildStatusEnabled: Bool { didSet { defaults.set(xcodeBuildStatusEnabled, forKey: Key.xcodeBuildStatusEnabled) } }
    var buildFailureSound: Bool { didSet { defaults.set(buildFailureSound, forKey: Key.buildFailureSound) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.openOnHover: true,
            Key.hoverDelay: 0.1,
            Key.hapticsEnabled: true,
            Key.showMusicActivity: true,
            Key.showChargingActivity: true,
            Key.lyricsEnabled: true,
            Key.lyricsUnderNotch: false,
            Key.lyricsPanelVisible: false,
            Key.replaceSystemHUD: true,
            Key.notificationAlertsEnabled: true,
            Key.alertSoundEnabled: true,
            Key.keepAwakeMode: KeepAwakeManager.Mode.whileAgentsWork.rawValue,
            Key.keepDisplayAwake: false,
            Key.agentFinishAlerts: true,
            Key.fullChargeAlert: true,
            Key.fullChargeTarget: 100,
            Key.xcodeBuildStatusEnabled: true,
            Key.buildFailureSound: true,
        ])
        openOnHover = defaults.bool(forKey: Key.openOnHover)
        hoverDelay = defaults.double(forKey: Key.hoverDelay)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        showMusicActivity = defaults.bool(forKey: Key.showMusicActivity)
        showChargingActivity = defaults.bool(forKey: Key.showChargingActivity)
        lyricsEnabled = defaults.bool(forKey: Key.lyricsEnabled)
        lyricsUnderNotch = defaults.bool(forKey: Key.lyricsUnderNotch)
        lyricsPanelVisible = defaults.bool(forKey: Key.lyricsPanelVisible)
        replaceSystemHUD = defaults.bool(forKey: Key.replaceSystemHUD)
        notificationAlertsEnabled = defaults.bool(forKey: Key.notificationAlertsEnabled)
        alertSoundEnabled = defaults.bool(forKey: Key.alertSoundEnabled)
        keepAwakeMode = KeepAwakeManager.Mode(rawValue: defaults.string(forKey: Key.keepAwakeMode) ?? "") ?? .whileAgentsWork
        keepDisplayAwake = defaults.bool(forKey: Key.keepDisplayAwake)
        agentFinishAlerts = defaults.bool(forKey: Key.agentFinishAlerts)
        fullChargeAlert = defaults.bool(forKey: Key.fullChargeAlert)
        fullChargeTarget = defaults.integer(forKey: Key.fullChargeTarget)
        xcodeBuildStatusEnabled = defaults.bool(forKey: Key.xcodeBuildStatusEnabled)
        buildFailureSound = defaults.bool(forKey: Key.buildFailureSound)
    }
}
