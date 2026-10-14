import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var notchController: NotchWindowController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOtherInstances()
        model.notch.openSettings = { [weak self] in self?.showSettings() }
        notchController = NotchWindowController(model: model)
        model.start()

        #if DEBUG
        // `-NotchOpenOnLaunch YES [-NotchOpenTab dev]` keeps the notch open for screenshots and layout work.
        if UserDefaults.standard.bool(forKey: "NotchOpenOnLaunch") {
            model.notch.isPinned = true
            let tab = UserDefaults.standard.string(forKey: "NotchOpenTab").flatMap(NotchViewModel.Tab.init(rawValue:))
            model.notch.open(tab: tab)
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
        model.updates.checkForUpdates()
    }

    func showSettings() {
        model.notch.close()

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
}
