import AppKit

/// A private window-server space that sits above every desktop.
///
/// A window that merely "joins all Spaces" is copied onto each desktop and slides away with it
/// during a Spaces swipe. A window placed in its own top-level space stays put while the
/// desktops move underneath, just like the physical notch. This uses private SkyLight calls,
/// loaded dynamically. If they're missing, the window keeps its normal Spaces behavior.
final class NotchSpace {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceDestroy = @convention(c) (Int32, UInt64) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias WindowsSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

    private let connection: Int32
    private let space: UInt64
    private let addWindows: WindowsSpaces
    private let removeWindows: WindowsSpaces
    private let destroySpace: SpaceDestroy

    /// Returns `nil` if the private API isn't available on this macOS version.
    init?() {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainConnection: MainConnectionID = Self.symbol(skyLight, "SLSMainConnectionID"),
              let create: SpaceCreate = Self.symbol(skyLight, "SLSSpaceCreate"),
              let destroy: SpaceDestroy = Self.symbol(skyLight, "SLSSpaceDestroy"),
              let setLevel: SpaceSetAbsoluteLevel = Self.symbol(skyLight, "SLSSpaceSetAbsoluteLevel"),
              let show: ShowSpaces = Self.symbol(skyLight, "SLSShowSpaces"),
              let add: WindowsSpaces = Self.symbol(skyLight, "SLSAddWindowsToSpaces"),
              let remove: WindowsSpaces = Self.symbol(skyLight, "SLSRemoveWindowsFromSpaces")
        else { return nil }

        connection = mainConnection()
        space = create(connection, 1, nil)
        guard space != 0 else { return nil }

        addWindows = add
        removeWindows = remove
        destroySpace = destroy

        _ = setLevel(connection, space, Int32.max)
        _ = show(connection, [space] as CFArray)
    }

    deinit {
        _ = destroySpace(connection, space)
    }

    func add(_ window: NSWindow) {
        _ = addWindows(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    func remove(_ window: NSWindow) {
        _ = removeWindows(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
    }
}
