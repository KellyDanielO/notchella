import AppKit
import IOKit.ps
import notify
import SwiftUI

/// Watches the internal battery. Briefly flags a charging activity when power is connected,
/// a "charged" activity when the battery reaches the target level while plugged in, and, like the
/// iPhone, a low battery warning at 20% and 10% that offers to turn on Low Power Mode.
@Observable
final class BatteryManager {
    private(set) var hasBattery = false
    private(set) var level = 100
    private(set) var isCharging = false
    private(set) var isPluggedIn = false
    private(set) var isShowingChargingActivity = false
    private(set) var isShowingChargedActivity = false
    /// The level a low battery warning is showing for, or nil.
    private(set) var lowBatteryWarning: Int?
    private(set) var isLowPowerModeOn = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored var onPluggedIn: () -> Void = {}

    @ObservationIgnored private var notifyToken: Int32 = NOTIFY_TOKEN_INVALID
    @ObservationIgnored private var activityTask: Task<Void, Never>?
    @ObservationIgnored private var chargedTask: Task<Void, Never>?
    @ObservationIgnored private var lowBatteryTask: Task<Void, Never>?
    @ObservationIgnored private var powerStateObserver: NSObjectProtocol?

    private static let lowBatteryLevels = [20, 10]

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        update(announceChanges: false)
        // Posted by the system whenever any power source property changes.
        notify_register_dispatch(kIOPSNotifyAnyPowerSource, &notifyToken, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(announceChanges: true) }
        }
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            let isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
            withAnimation(.smooth) { self?.isLowPowerModeOn = isOn }
        }
    }

    private func update(announceChanges: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue

            hasBattery = true
            let previousLevel = level
            level = Int((Double(current) / Double(maximum) * 100).rounded())
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            if announceChanges && pluggedIn && !isPluggedIn {
                onPluggedIn()
                showChargingActivity()
                dismissLowBatteryWarning()
            }
            if announceChanges && settings.lowBatteryAlert && !pluggedIn,
               let crossed = Self.lowBatteryLevels.first(where: { previousLevel > $0 && level <= $0 }) {
                showLowBatteryWarning(crossed)
            }
            isPluggedIn = pluggedIn

            let target = min(max(settings.fullChargeTarget, 50), 100)
            if announceChanges && settings.fullChargeAlert && pluggedIn && previousLevel < target && level >= target {
                showChargedActivity()
            }
            return
        }
    }

    func dismissLowBatteryWarning() {
        lowBatteryTask?.cancel()
        guard lowBatteryWarning != nil else { return }
        withAnimation(.notchActivity) { lowBatteryWarning = nil }
    }

    /// Turns on Low Power Mode while on battery. Changing it needs an administrator, so macOS asks
    /// for Touch ID or the password first; if that's cancelled nothing changes.
    func turnOnLowPowerMode() {
        dismissLowBatteryWarning()
        NSApp.activate()
        Task.detached(priority: .userInitiated) {
            let script = NSAppleScript(source: "do shell script \"/usr/bin/pmset -b lowpowermode 1\" with administrator privileges")
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
        }
    }

    #if DEBUG
    func simulateLowBattery() {
        level = 20
        showLowBatteryWarning(20)
    }
    #endif

    private func showLowBatteryWarning(_ level: Int) {
        NSSound(named: "Tink")?.play()
        lowBatteryTask?.cancel()
        withAnimation(.notchActivity) { lowBatteryWarning = level }
        lowBatteryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            withAnimation(.notchActivity) { self?.lowBatteryWarning = nil }
        }
    }

    private func showChargedActivity() {
        NSSound(named: "Purr")?.play()
        chargedTask?.cancel()
        withAnimation(.notchActivity) { isShowingChargedActivity = true }
        chargedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.notchActivity) { self?.isShowingChargedActivity = false }
        }
    }

    private func showChargingActivity() {
        activityTask?.cancel()
        withAnimation(.notchActivity) { isShowingChargingActivity = true }
        activityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.notchActivity) { self?.isShowingChargingActivity = false }
        }
    }
}
