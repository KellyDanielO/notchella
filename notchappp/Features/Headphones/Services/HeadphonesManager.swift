import AppKit
import CoreAudio
import SwiftUI

nonisolated struct HeadphoneDevice: Equatable, Sendable {
    let name: String
    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    /// AirPods-style devices report each bud separately.
    var hasSeparateBuds: Bool { left != nil || right != nil }

    /// The level that matters most: the emptiest bud, or the only battery.
    var lowestLevel: Int? { [main, left, right].compactMap { $0 }.min() }

    var symbol: String {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return "airpods.max" }
        if lowered.contains("airpods pro") { return "airpods.pro" }
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("beats") { return "beats.headphones" }
        return "headphones"
    }
}

/// Notices Bluetooth headphones and earbuds, and reads their battery levels.
///
/// Connection is detected without any Bluetooth permission: when headphones connect, macOS
/// switches the default audio output to them, and Core Audio reports that the new output is a
/// Bluetooth device. Battery levels come from the system's Bluetooth report (`system_profiler`),
/// which includes left/right/case for AirPods and a single level for most other headsets.
@Observable
final class HeadphonesManager {
    private(set) var device: HeadphoneDevice?
    /// True for a few seconds after headphones connect.
    private(set) var isShowingConnection = false
    /// True for a few seconds when a battery drops to the warning level.
    private(set) var isShowingLowBattery = false

    static let lowBatteryLevel = 15

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var warnedDeviceName: String?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputDidChange(announce: true) }
        }
        outputDidChange(announce: false)

        // Battery drains slowly; a refresh every two minutes is plenty.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBattery(announce: false) }
        }
    }

    var isShowingActivity: Bool {
        settings.headphonesActivity && device != nil && (isShowingConnection || isShowingLowBattery)
    }

    // MARK: Connection

    private func outputDidChange(announce: Bool) {
        guard let output = Self.defaultOutput(), output.isBluetooth else {
            if device != nil {
                withAnimation(.notchActivity) {
                    device = nil
                    isShowingConnection = false
                    isShowingLowBattery = false
                }
            }
            return
        }
        guard output.name != device?.name else { return }

        withAnimation(.notchActivity) { device = HeadphoneDevice(name: output.name) }
        if announce { flash(\.isShowingConnection, seconds: 4) }
        // The headset reports its battery a moment after connecting.
        Task { [weak self] in
            self?.refreshBattery(announce: announce)
            try? await Task.sleep(for: .seconds(2))
            self?.refreshBattery(announce: announce)
        }
    }

    private func refreshBattery(announce: Bool) {
        guard let name = device?.name else { return }
        Task {
            let report = await Task.detached(priority: .utility) { Self.readBatteries(preferring: name) }.value
            guard let report, device?.name == name else { return }

            withAnimation(.smooth) {
                device?.main = report.main
                device?.left = report.left
                device?.right = report.right
                device?.caseLevel = report.caseLevel
            }

            if let lowest = device?.lowestLevel, lowest <= Self.lowBatteryLevel, warnedDeviceName != name {
                warnedDeviceName = name
                flash(\.isShowingLowBattery, seconds: 5)
                if settings.alertSoundEnabled { NSSound(named: "Funk")?.play() }
            }
        }
    }

    private func flash(_ keyPath: ReferenceWritableKeyPath<HeadphonesManager, Bool>, seconds: Double) {
        guard settings.headphonesActivity else { return }
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        flashTask?.cancel()
        withAnimation(.notchActivity) { self[keyPath: keyPath] = true }
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.notchActivity) { self?[keyPath: keyPath] = false }
        }
    }

    // MARK: Core Audio

    private nonisolated static func defaultOutput() -> (name: String, isBluetooth: Bool)? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown
        else { return nil }

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)

        let isBluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        return ((name?.takeRetainedValue() as String?) ?? "Headphones", isBluetooth)
    }

    // MARK: Battery report

    private nonisolated struct BatteryReport: Sendable {
        var main: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?
    }

    /// Reads connected Bluetooth devices' batteries, preferring the one named like the audio output.
    private nonisolated static func readBatteries(preferring name: String) -> BatteryReport? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controller = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = controller["device_connected"] as? [[String: [String: Any]]]
        else { return nil }

        let devices = connected.flatMap { $0.map { (name: $0.key, info: $0.value) } }
        let reports = devices.map { device in
            (name: device.name, report: BatteryReport(
                main: level(device.info["device_batteryLevelMain"]),
                left: level(device.info["device_batteryLevelLeft"]),
                right: level(device.info["device_batteryLevelRight"]),
                caseLevel: level(device.info["device_batteryLevelCase"])
            ))
        }
        let hasLevels: (BatteryReport) -> Bool = { $0.main != nil || $0.left != nil || $0.right != nil }
        return (reports.first { $0.name == name && hasLevels($0.report) }
            ?? reports.first { hasLevels($0.report) })?.report
    }

    private nonisolated static func level(_ value: Any?) -> Int? {
        (value as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
    }
}
