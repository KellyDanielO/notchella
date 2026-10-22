import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var notchController: NotchWindowController?
    private var settingsWindow: NSWindow?
    private var batteryReportWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOtherInstances()
        model.notch.openSettings = { [weak self] in self?.showSettings() }
        model.notch.openBatteryReport = { [weak self] in self?.showBatteryReport() }
        notchController = NotchWindowController(model: model)
        model.start()
        Analytics.start(settings: model.settings)

        #if DEBUG
        // `-NotchOpenOnLaunch YES [-NotchOpenTab dev]` keeps the notch open for screenshots and layout work.
        if UserDefaults.standard.bool(forKey: "NotchOpenOnLaunch") {
            model.notch.isPinned = true
            let tab = UserDefaults.standard.string(forKey: "NotchOpenTab").flatMap(NotchViewModel.Tab.init(rawValue:))
            model.notch.open(tab: tab)
        }
        // `-NotchSimulate offline|online|lowBattery|batteryReport` shows that activity without the real event.
        switch UserDefaults.standard.string(forKey: "NotchSimulate") {
        case "offline": model.network.simulate(online: false)
        case "online": model.network.simulate(online: true)
        case "lowBattery": model.battery.simulateLowBattery()
        case "batteryReport": showBatteryReport()
        default: break
        }
        #endif
    }

    /// Two copies would draw two notches on top of each other, fighting over hover and animation.
    /// The newest launch wins, so re-running from Xcode replaces the previous copy.
    private func quitOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = NSRunningApplication.current.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where app.processIdentifier != current {
            app.terminate()
        }
    }

    func checkForUpdates() {
        Analytics.track("update_check")
        model.updates.checkForUpdates()
    }

    func showSettings() {
        model.notch.close()
        Analytics.track("settings_opened")

        if settingsWindow == nil {
            let root = SettingsView()
                .environment(model.settings)
                .environment(model.updates)
                .environment(model.calendar)
                .environment(model.hud)
                .environment(model.alerts)
                .environment(model.agents)
                .environment(model.idle)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Notch Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showBatteryReport() {
        model.notch.close()
        Analytics.track("battery_report_opened")

        // A fresh view each time so it measures again.
        let controller = NSHostingController(rootView: BatteryReportView())
        if let window = batteryReportWindow {
            window.contentViewController = controller
        } else {
            let window = NSWindow(contentViewController: controller)
            window.title = "Battery Report"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.setContentSize(NSSize(width: 400, height: 640))
            window.center()
            batteryReportWindow = window
        }

        NSApp.activate()
        batteryReportWindow?.makeKeyAndOrderFront(nil)
    }
}
