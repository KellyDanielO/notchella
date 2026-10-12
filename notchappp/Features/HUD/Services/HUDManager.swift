import AppKit
import ApplicationServices
import SwiftUI

/// Replaces the system volume and brightness HUD with one shown in the notch.
@Observable
final class HUDManager {
    /// The HUD currently on screen, or `nil` when hidden.
    private(set) var visibleKind: HUDKind?
    private(set) var volume: Float = 0
    private(set) var isMuted = false
    private(set) var brightness: Float = 0
    private(set) var isAccessibilityTrusted = AXIsProcessTrusted()

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private lazy var keyTap = MediaKeyTap { [weak self] key, isKeyDown, isRepeat, modifiers in
        self?.handle(key, isKeyDown: isKeyDown, isRepeat: isRepeat, modifiers: modifiers) ?? false
    }
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var brightnessRamp: Task<Void, Never>?
    @ObservationIgnored private var trustPollTimer: Timer?

    /// macOS uses 16 steps per full range, or 64 with Option+Shift held.
    private static let coarseStep: Float = 1 / 16
    private static let fineStep: Float = 1 / 64

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// The level shown on the bar for the visible HUD.
    var level: Float {
        switch visibleKind {
        case .volume: isMuted ? 0 : volume
        case .brightness: brightness
        case nil: 0
        }
    }

    func start() {
        guard settings.replaceSystemHUD else { return }
        if keyTap.start() {
            isAccessibilityTrusted = true
        } else {
            requestAccessibilityAccess()
        }
    }

    /// Shows the system prompt (first time only), then waits for the user to grant access.
    func requestAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        guard !isAccessibilityTrusted, trustPollTimer == nil else {
            if isAccessibilityTrusted { keyTap.start() }
            return
        }

        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                timer.invalidate()
                self.trustPollTimer = nil
                self.isAccessibilityTrusted = true
                self.keyTap.start()
            }
        }
    }

    // MARK: Key handling

    private func handle(_ key: MediaKey, isKeyDown: Bool, isRepeat: Bool, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard settings.replaceSystemHUD else { return false }

        // Hand keys we can't act on back to the system (external display, fixed-volume device).
        switch key.kind {
        case .volume: guard SystemAudio.canControlVolume else { return false }
        case .brightness: guard DisplayBrightness.isAvailable else { return false }
        }

        // Swallow key-ups too, so the system never sees half a key press.
        guard isKeyDown else { return true }

        let step = modifiers.isSuperset(of: [.option, .shift]) ? Self.fineStep : Self.coarseStep
        switch key {
        case .volumeUp: changeVolume(by: step)
        case .volumeDown: changeVolume(by: -step)
        case .mute: if !isRepeat { toggleMute() }
        case .brightnessUp: changeBrightness(by: step)
        case .brightnessDown: changeBrightness(by: -step)
        }

        show(key.kind)
        return true
    }

    private func changeVolume(by delta: Float) {
        var newVolume = Self.snap(SystemAudio.volume + delta, to: abs(delta))
        if SystemAudio.isMuted && delta > 0 {
            SystemAudio.isMuted = false
            newVolume = max(newVolume, abs(delta))
        }
        SystemAudio.volume = newVolume
        // Hitting zero mutes, like the system does.
        if newVolume == 0 { SystemAudio.isMuted = true }
        refreshVolume()
    }

    private func toggleMute() {
        SystemAudio.isMuted.toggle()
        refreshVolume()
    }

    private func refreshVolume() {
        withAnimation(.smooth(duration: 0.15)) {
            volume = SystemAudio.volume
            isMuted = SystemAudio.isMuted
        }
    }

    private func changeBrightness(by delta: Float) {
        let start = brightnessRamp == nil ? DisplayBrightness.brightness : brightness
        let target = Self.snap(start + delta, to: abs(delta))
        withAnimation(.smooth(duration: 0.15)) { brightness = target }

        // Ease into the new level so the screen doesn't visibly jump.
        brightnessRamp?.cancel()
        brightnessRamp = Task { [weak self] in
            let steps = 6
            for index in 1...steps {
                guard !Task.isCancelled else { return }
                DisplayBrightness.brightness = start + (target - start) * Float(index) / Float(steps)
                try? await Task.sleep(for: .milliseconds(14))
            }
            self?.brightnessRamp = nil
        }
    }

    private func show(_ kind: HUDKind) {
        if visibleKind != kind {
            withAnimation(.notchActivity) { visibleKind = kind }
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.notchActivity) { self?.visibleKind = nil }
        }
    }

    /// Rounds to the step grid, so values like 0.49 land on 0.5 after one press.
    private static func snap(_ value: Float, to step: Float) -> Float {
        min(max((value / step).rounded() * step, 0), 1)
    }
}
