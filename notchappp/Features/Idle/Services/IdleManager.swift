import SwiftUI

/// What the closed notch does when nothing else is going on: occasional ambient affirmations,
/// and the moods and blinks of the notch's eyes.
@Observable
final class IdleManager {
    enum EyeMood {
        case normal
        case sleepy
        case surprised
    }

    /// The affirmation currently drifting through the notch, if any.
    private(set) var ambientAffirmation: String?
    private(set) var isBlinking = false
    private(set) var isSurprised = false

    /// Set by the app model: whether showing an ambient affirmation now would interrupt something.
    @ObservationIgnored var canShowAmbient: () -> Bool = { true }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let reflect: ReflectStore
    @ObservationIgnored private var lastAmbientDate = Date()
    @ObservationIgnored private var lastAmbientText: String?
    @ObservationIgnored private var ambientTimer: Timer?
    @ObservationIgnored private var blinkTask: Task<Void, Never>?
    @ObservationIgnored private var surpriseTask: Task<Void, Never>?

    private static let ambientDuration: TimeInterval = 8

    init(settings: AppSettings, reflect: ReflectStore) {
        self.settings = settings
        self.reflect = reflect
    }

    func start() {
        ambientTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.considerAmbientAffirmation() }
        }
        startBlinking()
    }

    // MARK: Eyes

    var eyeMood: EyeMood {
        if isSurprised { return .surprised }
        let hour = Calendar.current.component(.hour, from: .now)
        return hour >= 23 || hour < 6 ? .sleepy : .normal
    }

    /// Wide eyes for a few seconds, e.g. when the charger is plugged in.
    func surprise() {
        surpriseTask?.cancel()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { isSurprised = true }
        surpriseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { self?.isSurprised = false }
        }
    }

    /// Blinks at random intervals, sometimes twice in a row, the way people do.
    private func startBlinking() {
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                let sleepy = self?.eyeMood == .sleepy
                try? await Task.sleep(for: .seconds(Double.random(in: sleepy ? 1.5...3.5 : 2.5...6.5)))
                guard let self, settings.idleEyes else { continue }
                await blink(duration: sleepy ? 0.35 : 0.14)
                if Int.random(in: 0..<5) == 0 {
                    try? await Task.sleep(for: .milliseconds(160))
                    await blink(duration: 0.12)
                }
            }
        }
    }

    private func blink(duration: TimeInterval) async {
        withAnimation(.easeIn(duration: duration * 0.45)) { isBlinking = true }
        try? await Task.sleep(for: .seconds(duration))
        withAnimation(.easeOut(duration: duration * 0.55)) { isBlinking = false }
    }

    // MARK: Ambient affirmations

    func showAmbientAffirmationNow() {
        let choices = reflect.affirmations.map(\.text).filter { $0 != lastAmbientText }
        guard let text = choices.randomElement() ?? reflect.affirmations.first?.text else { return }
        lastAmbientDate = Date()
        lastAmbientText = text
        withAnimation(.notchOpen) { ambientAffirmation = text }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.ambientDuration))
            withAnimation(.notchClose) { self?.ambientAffirmation = nil }
        }
    }

    func dismissAmbientAffirmation() {
        withAnimation(.notchClose) { ambientAffirmation = nil }
    }

    private func considerAmbientAffirmation() {
        let interval = TimeInterval(max(settings.ambientAffirmationMinutes, 5) * 60)
        guard settings.ambientAffirmations,
              ambientAffirmation == nil,
              !reflect.affirmations.isEmpty,
              Date().timeIntervalSince(lastAmbientDate) >= interval,
              canShowAmbient()
        else { return }
        showAmbientAffirmationNow()
    }
}
