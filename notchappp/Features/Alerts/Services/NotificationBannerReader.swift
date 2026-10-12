import AppKit
import ApplicationServices

/// The text of one notification banner as read from the screen.
nonisolated struct NotificationBanner: Sendable {
    /// The posting app's name, when the banner's accessibility description includes it.
    let appName: String?
    let texts: [String]

    var title: String { texts.first ?? "" }
    var body: String { texts.dropFirst().joined(separator: " ") }
    /// Everything rules match against, app name included, so a rule can target an app.
    var fullText: String { ([appName].compactMap { $0 } + texts).joined(separator: " ") }
}

/// Reads notification banners as they appear by walking Notification Center's accessibility tree.
///
/// macOS gives apps no API for other apps' notifications. A banner is ordinary on-screen UI,
/// though, so with Accessibility access its text can be read like a screen reader would.
/// Banners are elements with the `AXNotificationCenterBanner` subrole inside the
/// Notification Center app, whose description reads "App, Title, Body".
final class NotificationBannerReader {
    private static let notificationCenterID = "com.apple.notificationcenterui"

    var onBanner: (NotificationBanner) -> Void = { _ in }

    private let queue = DispatchQueue(label: "com.kellydaniel.notchappp.banners", qos: .utility)
    private var timer: Timer?
    private var seen: [String: Date] = [:]
    private var hasBaseline = false
    private var isScanning = false

    /// More banners than this at once means the Notification Center history panel is open.
    /// Those are old notifications, so they're recorded as seen but never alerted on.
    private static let maxLiveBanners = 3

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hasBaseline = false
    }

    private func scan() {
        guard !isScanning, AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.notificationCenterID).first?.processIdentifier
        else { return }

        isScanning = true
        queue.async { [weak self] in
            // Accessibility calls block, so the tree walk happens off the main thread.
            let banners = Self.readBanners(pid: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.process(banners) }
            }
        }
    }

    private func process(_ banners: [NotificationBanner]) {
        isScanning = false
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 600 }

        // Banners already on screen at launch, or listed in the history panel, only set the baseline.
        let shouldAlert = hasBaseline && banners.count <= Self.maxLiveBanners
        for banner in banners {
            let signature = banner.fullText
            guard seen[signature] == nil else { continue }
            seen[signature] = now
            if shouldAlert { onBanner(banner) }
        }
        hasBaseline = true
    }

    // MARK: Accessibility tree walking

    private nonisolated static func readBanners(pid: pid_t) -> [NotificationBanner] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)

        var banners: [NotificationBanner] = []
        for window in children(of: app, attribute: kAXWindowsAttribute) {
            for element in notificationElements(in: window, depth: 0) {
                var texts: [String] = []
                collectText(in: element, depth: 0, into: &texts)
                guard !texts.isEmpty else { continue }
                let description = string(element, kAXDescriptionAttribute)
                banners.append(NotificationBanner(appName: appName(from: description, texts: texts), texts: texts))
            }
        }
        return banners
    }

    /// The description is "App, Title, Body"; whatever precedes the texts is the app name.
    private nonisolated static func appName(from description: String?, texts: [String]) -> String? {
        guard let description, let first = texts.first,
              let range = description.range(of: ", " + first)
        else { return nil }
        let name = String(description[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Elements whose subrole marks them as a notification (`AXNotificationCenterBanner`,
    /// `AXNotificationCenterAlert`). Desktop widgets live in the same app and are skipped.
    private nonisolated static func notificationElements(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < 12 else { return [] }
        if let subrole = string(element, kAXSubroleAttribute), subrole.hasPrefix("AXNotificationCenter") {
            return [element]
        }
        return children(of: element, attribute: kAXChildrenAttribute)
            .flatMap { notificationElements(in: $0, depth: depth + 1) }
    }

    private nonisolated static func collectText(in element: AXUIElement, depth: Int, into texts: inout [String]) {
        guard depth < 12, texts.count < 12 else { return }
        if string(element, kAXRoleAttribute) == kAXStaticTextRole,
           let value = string(element, kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty, !texts.contains(value) {
            texts.append(value)
        }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            collectText(in: child, depth: depth + 1, into: &texts)
        }
    }

    private nonisolated static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

}
