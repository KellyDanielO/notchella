import AppKit
import SwiftUI

/// Hosts the notch UI and routes global mouse movement to the view model.
///
/// The panel stays a fixed size. Only the SwiftUI shape inside it animates, which keeps
/// motion smooth. Clicks pass through everywhere except the visible notch.
final class NotchWindowController {
    private let panel = NotchPanel()
    private let space = NotchSpace()
    private let model: AppModel
    private var eventMonitors: [Any] = []
    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
    /// Dragging a file out of the notch (from the Shelf or the Images tray) shouldn't
    /// bring up the drop zones under it.
    private var dragStartedInNotch = false

    init(model: AppModel) {
        self.model = model

        let root = NotchRootView()
            .environment(model.notch)
            .environment(model.settings)
            .environment(model.music)
            .environment(model.lyrics)
            .environment(model.battery)
            .environment(model.calendar)
            .environment(model.shelf)
            .environment(model.imageTools)
            .environment(model.hud)
            .environment(model.alerts)
            .environment(model.reflect)
            .environment(model.agents)
            .environment(model.xcode)
            .environment(model.keepAwake)
            .environment(model.devServers)
            .environment(model.headphones)
            .environment(model.downloads)
            .environment(model.idle)
            .environment(\.colorScheme, .dark)
            .fontDesign(.rounded)
        let hostingView = NotchHostingView(rootView: root)
        hostingView.sizingOptions = []
        // As a window's content view, NSHostingView resizes the window to fit the SwiftUI content.
        // When the notch's size changes mid-layout, that feeds back into another layout pass until
        // AppKit throws ("more Update Constraints in Window passes than there are views").
        // A plain container keeps the window's size fixed.
        let container = NSView(frame: NSRect(origin: .zero, size: NotchViewModel.windowSize))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container

        model.notch.didClose = { [weak self] in self?.returnKeyboardFocus() }

        positionPanel()
        panel.orderFrontRegardless()
        space?.add(panel)
        startTrackingMouse()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionPanel() }
        }
    }

    deinit {
        eventMonitors.forEach(NSEvent.removeMonitor)
        pollTimer?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    // MARK: Positioning

    /// Prefers the built-in display with a notch, falling back to the main display.
    private func positionPanel() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        model.notch.configure(for: screen)

        let size = NotchViewModel.windowSize
        panel.setFrame(
            NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    /// After a click made the panel key, hand the keyboard back to the app you were using.
    private func returnKeyboardFocus() {
        guard panel.isKeyWindow else { return }
        panel.resignKey()
        NSWorkspace.shared.frontmostApplication?.activate()
    }

    // MARK: Mouse tracking

    private func startTrackingMouse() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown]

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, isGlobal: true) }
        }) {
            eventMonitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event, isGlobal: false)
            return event
        }) {
            eventMonitors.append(monitor)
        }

        // Safety net for events the monitors miss (e.g. during another app's drag session).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func handle(_ event: NSEvent, isGlobal: Bool) {
        let location = NSEvent.mouseLocation

        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
            dragStartedInNotch = model.notch.status == .open && model.notch.hitRect.contains(location)
            if isGlobal && model.notch.status == .open && !model.notch.hitRect.contains(location) {
                model.notch.close()
            }
        }
        update(at: location)
    }

    private func update(at location: CGPoint = NSEvent.mouseLocation) {
        model.notch.handleMouse(at: location, isDraggingFiles: isDraggingFiles)

        let accepts = model.notch.hitRect.contains(location) || model.notch.isDropTargeted
        if panel.ignoresMouseEvents == accepts {
            panel.ignoresMouseEvents = !accepts
        }
    }

    /// True while the left button is down and a drag that started after the last click carries files.
    private var isDraggingFiles: Bool {
        guard NSEvent.pressedMouseButtons & 1 == 1, !dragStartedInNotch else { return false }
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.changeCount != dragPasteboardChangeCount
            && (pasteboard.types?.contains(.fileURL) ?? false)
    }
}
