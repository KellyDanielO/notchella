import AppKit
import SwiftUI

/// A transparent, borderless panel that floats above the menu bar on every Space.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit spends the first click on a non-key window just making it key, so buttons
    /// would need two clicks. Becoming key first lets every click land.
    /// The panel is non-activating, so the app you're in stays frontmost.
    override func sendEvent(_ event: NSEvent) {
        if !isKeyWindow, [.leftMouseDown, .rightMouseDown].contains(event.type) {
            makeKey()
        }
        super.sendEvent(event)
    }
}

/// Lets the first click land on a control even though the panel isn't key.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
