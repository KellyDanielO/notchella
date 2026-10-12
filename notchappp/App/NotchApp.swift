import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Notch", systemImage: "rectangle.topthird.inset.filled") {
            Button("Settings…") { appDelegate.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Notch") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
