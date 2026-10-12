import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Notch", systemImage: "rectangle.topthird.inset.filled") {
            Button("Settings…") { appDelegate.showSettings() }
                .keyboardShortcut(",")
            Button("Check for Updates…") { appDelegate.checkForUpdates() }
            Divider()
            Button("About Notchella…") { appDelegate.showSettings() }
            Button("More Apps by Kelly Daniel…") { NSWorkspace.shared.open(Developer.appsPage) }
            Button("Contact the Developer…") { NSWorkspace.shared.open(Developer.mailURL) }
            Divider()
            Button("Quit Notch") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
