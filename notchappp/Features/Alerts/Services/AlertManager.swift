import AppKit
import SwiftUI

/// Matches incoming notification banners against keyword rules and shows hits in the notch.
@Observable
final class AlertManager {
    private(set) var rules: [AlertRule] = []
    private(set) var currentAlert: NotchAlert?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let reader = NotificationBannerReader()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private static let storageKey = "alertRules"

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([AlertRule].self, from: data) {
            rules = saved
        }
        reader.onBanner = { [weak self] banner in self?.handle(banner) }
    }

    func start() {
        if settings.notificationAlertsEnabled {
            reader.start()
        } else {
            reader.stop()
        }
    }

    // MARK: Rules

    func addRule() {
        rules.append(AlertRule(keywords: ""))
        save()
    }

    func update(_ rule: AlertRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save()
    }

    func remove(_ rule: AlertRule) {
        rules.removeAll { $0.id == rule.id }
        save()
    }

    // MARK: Alerts

    func preview() {
        present(NotchAlert(
            appName: "Messages",
            title: "Mum",
            body: "Call me when you're free, it's urgent",
            matchedTerms: ["urgent"]
        ))
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.notchActivity) { currentAlert = nil }
    }

    private func handle(_ banner: NotificationBanner) {
        guard settings.notificationAlertsEnabled else { return }
        for rule in rules {
            if let terms = rule.matches(in: banner.fullText) {
                present(NotchAlert(appName: banner.appName, title: banner.title, body: banner.body, matchedTerms: terms))
                return
            }
        }
    }

    private func present(_ alert: NotchAlert) {
        withAnimation(.notchOpen) { currentAlert = alert }
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if settings.alertSoundEnabled {
            NSSound(named: "Glass")?.play()
        }

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
