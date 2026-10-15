import Aptabase
import Foundation

/// Anonymous usage counts, sent to Aptabase (no personal data, no device identifier).
///
/// Notchella runs for days without relaunching and the notch opens on every hover, so most events
/// are sent at most once a day: enough to count daily active users and see which parts get used,
/// without one event per hover eating the event quota. Respects the "Share anonymous usage data"
/// setting, which is read straight from `UserDefaults` so it applies before `AppSettings` exists.
enum Analytics {
    static let enabledKey = "shareUsageData"

    private static let appKey = "A-US-9870459032"
    private static let lastSentKey = "analyticsLastSent"
    private static var heartbeat: Timer?

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func start(settings: AppSettings) {
        Aptabase.shared.initialize(appKey: appKey)
        track("app_started", with: [
            "glassDesign": settings.glassDesign,
            "openOnHover": settings.openOnHover,
            "lyrics": settings.lyricsEnabled,
            "replaceSystemHUD": settings.replaceSystemHUD,
            "xcodeBuildStatus": settings.xcodeBuildStatusEnabled,
            "notificationAlerts": settings.notificationAlertsEnabled,
            "idleEyes": settings.idleEyes,
        ])
        trackDaily("app_active")
        // The Mac may stay on past midnight, so check again every hour.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            trackDaily("app_active")
        }
    }

    static func track(_ event: String, with props: [String: Value] = [:]) {
        guard isEnabled else { return }
        Aptabase.shared.trackEvent(event, with: props)
    }

    /// Sends `event` (with these props) only the first time it happens each calendar day.
    static func trackDaily(_ event: String, with props: [String: Value] = [:]) {
        let id = ([event] + props.keys.sorted().map { "\($0)=\(props[$0]!)" }).joined(separator: "|")
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        var lastSent = UserDefaults.standard.dictionary(forKey: lastSentKey) as? [String: Double] ?? [:]
        guard lastSent[id] != today, isEnabled else { return }
        lastSent[id] = today
        UserDefaults.standard.set(lastSent, forKey: lastSentKey)
        Aptabase.shared.trackEvent(event, with: props)
    }
}
