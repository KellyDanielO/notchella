import CoreGraphics
import Darwin

/// Built-in display brightness via the private DisplayServices framework (the same API
/// Control Center uses). External monitors aren't supported; their keys go to the system.
nonisolated enum DisplayBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    nonisolated(unsafe) private static let framework = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )
    private static let getBrightness: GetBrightness? = symbol("DisplayServicesGetBrightness")
    private static let setBrightness: SetBrightness? = symbol("DisplayServicesSetBrightness")

    static var isAvailable: Bool {
        builtInDisplay != nil && getBrightness != nil && setBrightness != nil
    }

    static var brightness: Float {
        get {
            guard let display = builtInDisplay, let getBrightness else { return 0 }
            var value: Float = 0
            return getBrightness(display, &value) == 0 ? value : 0
        }
        set {
            guard let display = builtInDisplay, let setBrightness else { return }
            _ = setBrightness(display, min(max(newValue, 0), 1))
        }
    }

    private static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let framework, let pointer = dlsym(framework, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
