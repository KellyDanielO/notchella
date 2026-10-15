import SwiftUI

struct NetworkClosedLeading: View {
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        Image(systemName: network.isShowingOnlineActivity ? "wifi" : "wifi.slash")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(network.isShowingOnlineActivity ? .green : .orange)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, options: .nonRepeating, value: network.isShowingOnlineActivity)
    }
}

struct NetworkClosedTrailing: View {
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        Text(network.isShowingOnlineActivity ? "Online" : "Offline")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(network.isShowingOnlineActivity ? .green : .orange)
            .contentTransition(.interpolate)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Stays in the open notch's header for as long as the Mac is offline.
struct NetworkHeaderBadge: View {
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        if !network.isOnline {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)
                .help("No internet connection")
                .transition(.scale.combined(with: .opacity))
        }
    }
}
