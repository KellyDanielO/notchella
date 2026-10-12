import AppKit
import ApplicationServices

/// Intercepts volume and brightness keys with a Quartz event tap.
///
/// The handler returns `true` to swallow a key, which also suppresses the system HUD.
/// Requires Accessibility permission.
final class MediaKeyTap {
    typealias Handler = (_ key: MediaKey, _ isKeyDown: Bool, _ isRepeat: Bool, _ modifiers: NSEvent.ModifierFlags) -> Bool

    private let handler: Handler
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool { tap != nil }

    /// Installs the tap. Fails (returns `false`) until Accessibility access is granted.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let systemDefinedMask = CGEventMask(1 << NX_SYSDEFINED)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: systemDefinedMask,
            callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        runLoopSource = source
        return true
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func handle(_ event: NSEvent) -> Bool {
        // Media keys arrive as system-defined events with subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS).
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return false }

        let data = event.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let keyFlags = data & 0x0000_FFFF
        let isKeyDown = (keyFlags & 0xFF00) >> 8 == 0xA
        let isRepeat = keyFlags & 0x1 == 1

        guard let key = MediaKey(rawValue: keyCode) else { return false }
        return handler(key, isKeyDown, isRepeat, event.modifierFlags)
    }
}

/// C callback for the event tap. It runs on the main run loop, where the tap's source is installed.
private nonisolated func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }

    return MainActor.assumeIsolated {
        let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()

        // The system disables slow or interrupted taps; turn it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tap.reenable()
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event), tap.handle(nsEvent) else {
            return Unmanaged.passUnretained(event)
        }
        return nil
    }
}
