import Network
import SwiftUI

/// Watches the internet connection. Briefly flags an "Offline" activity when it drops, and a
/// "Back online" one when it returns, like the iPhone's connection status in the Dynamic Island.
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private(set) var isShowingOfflineActivity = false
    private(set) var isShowingOnlineActivity = false

    var isShowingActivity: Bool { isShowingOfflineActivity || isShowingOnlineActivity }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var offlineTask: Task<Void, Never>?
    @ObservationIgnored private var activityTask: Task<Void, Never>?
    /// Whether "Offline" was actually shown, so "Back online" only follows a drop the user saw.
    @ObservationIgnored private var announcedOffline = false

    /// Wi-Fi drops for a moment on wake and when switching networks; only a longer drop is news.
    private static let offlineGrace: Duration = .seconds(3)

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async { self?.update(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor", qos: .utility))
    }

    private func update(online: Bool) {
        guard online != isOnline else { return }
        withAnimation(.notchActivity) { isOnline = online }
        offlineTask?.cancel()

        if online {
            guard announcedOffline else { return }
            announcedOffline = false
            show(online: true, for: .seconds(2.5))
        } else {
            offlineTask = Task { [weak self] in
                try? await Task.sleep(for: Self.offlineGrace)
                guard !Task.isCancelled, let self, !isOnline else { return }
                announcedOffline = true
                show(online: false, for: .seconds(4))
            }
        }
    }

    #if DEBUG
    /// Shows the activity without touching the network, for layout work.
    func simulate(online: Bool) {
        isOnline = online
        show(online: online, for: .seconds(30))
    }
    #endif

    private func show(online: Bool, for duration: Duration) {
        guard settings.networkActivity else { return }
        activityTask?.cancel()
        withAnimation(.notchActivity) {
            isShowingOnlineActivity = online
            isShowingOfflineActivity = !online
        }
        activityTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.notchActivity) {
                self?.isShowingOnlineActivity = false
                self?.isShowingOfflineActivity = false
            }
        }
    }
}
