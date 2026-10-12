import AppKit
import IOKit.ps
import notify
import SwiftUI

/// Watches the internal battery. Briefly flags a charging activity when power is connected,
/// and a "charged" activity when the battery reaches the target level while plugged in.
@Observable
final class BatteryManager {
    private(set) var hasBattery = false
    private(set) var level = 100
    private(set) var isCharging = false
    private(set) var isPluggedIn = false
    private(set) var isShowingChargingActivity = false
    private(set) var isShowingChargedActivity = false

    @ObservationIgnored private let settings: AppSettings

    @ObservationIgnored private var notifyToken: Int32 = NOTIFY_TOKEN_INVALID
    @ObservationIgnored private var activityTask: Task<Void, Never>?
    @ObservationIgnored private var chargedTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        update(announceChanges: false)
        // Posted by the system whenever any power source property changes.
        notify_register_dispatch(kIOPSNotifyAnyPowerSource, &notifyToken, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(announceChanges: true) }
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
                showChargingActivity()
            }
            isPluggedIn = pluggedIn

            let target = min(max(settings.fullChargeTarget, 50), 100)
            if announceChanges && settings.fullChargeAlert && pluggedIn && previousLevel < target && level >= target {
                showChargedActivity()
            }
            return
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
