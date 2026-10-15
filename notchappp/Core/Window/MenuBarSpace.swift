import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// Measures the free menu bar on each side of the notch: where the frontmost app's menus end on the
/// left, and where its overflow menus or the menu bar icons start on the right. The closed notch uses
/// it to keep its wings off long menu rows like Android Studio's, which wrap around the notch.
///
/// The app's menus are read through Accessibility (already granted for the HUD); without it the left
/// side is treated as free. Menu bar icons are read the same way, from each app's extras menu bar.
@Observable
final class MenuBarSpace {
    /// The right edge of the last menu title left of the notch, in screen coordinates.
    private(set) var leftItemsMaxX: CGFloat?
    /// The left edge of the first menu title or menu bar icon right of the notch, in screen coordinates.
    private(set) var rightItemsMinX: CGFloat?

    /// The screen holding the notch and the camera housing on it, set by the notch as it lays itself out.
    @ObservationIgnored private var screenFrame: CGRect = .zero
    @ObservationIgnored private var notchFrame: CGRect = .zero

    func configure(screen: CGRect, notch: CGRect) {
        guard screen != screenFrame || notch != notchFrame else { return }
        screenFrame = screen
        notchFrame = notch
        refresh()
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private let queue = DispatchQueue(label: "MenuBarSpace", qos: .utility)

    func start() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        // Apps swap menus without switching (Xcode while debugging, a browser's web app), and icons
        // come and go, so check again now and then too.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func refresh() {
        let screen = screenFrame
        let notch = notchFrame
        guard screen != .zero else { return }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = getpid()
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited && $0.processIdentifier != ownPID }
            .map(\.processIdentifier)
        queue.async { [weak self] in
            let menus = pid.map { Self.menuFrames(pid: $0) } ?? []
            let icons = Self.statusItemFrames(pids: pids)
            // Items that don't fit are tucked behind the camera housing by macOS and can't be covered.
            let left = menus.filter { $0.minX >= screen.minX && $0.maxX <= notch.minX + 1 }.map(\.maxX).max()
            let right = (menus + icons).filter { $0.minX >= notch.maxX - 1 && $0.maxX <= screen.maxX }.map(\.minX).min()
            DispatchQueue.main.async {
                guard let self, self.leftItemsMaxX != left || self.rightItemsMinX != right else { return }
                withAnimation(.notchActivity) {
                    self.leftItemsMaxX = left
                    self.rightItemsMinX = right
                }
            }
        }
    }

    /// The frontmost app's menu titles, Apple menu included.
    private nonisolated static func menuFrames(pid: pid_t) -> [CGRect] {
        guard AXIsProcessTrusted(), pid != getpid() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        return items(of: app, attribute: kAXMenuBarAttribute).compactMap { frame(of: $0) }.filter { $0.width > 0 }
    }

    /// Menu bar icons belong to the apps that put them there, each listed under its extras menu bar.
    private nonisolated static func statusItemFrames(pids: [pid_t]) -> [CGRect] {
        guard AXIsProcessTrusted() else { return [] }
        return pids.flatMap { pid -> [CGRect] in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.1)
            return items(of: app, attribute: "AXExtrasMenuBar").compactMap { frame(of: $0) }.filter { $0.width > 0 }
        }
    }

    private nonisolated static func items(of app: AXUIElement, attribute: String) -> [AXUIElement] {
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, attribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return [] }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success
        else { return [] }
        return children as? [AXUIElement] ?? []
    }

    private nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
