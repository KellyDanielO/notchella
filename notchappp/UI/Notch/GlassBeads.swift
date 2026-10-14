import SwiftUI

/// Circles beside the closed notch, one per activity running besides the one holding the wings,
/// like the Dynamic Island's detached second activity. They're ink, not glass: they sit on the
/// menu bar strip next to the camera, where the notch itself is black.
@available(macOS 26, *)
struct NotchSatellitesView: View {
    let activities: [NotchViewModel.Activity]
    let diameter: CGFloat

    var body: some View {
        HStack(spacing: NotchViewModel.satelliteGap) {
            ForEach(activities, id: \.self) { activity in
                SatelliteContent(kind: activity, diameter: diameter)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(.black))
                    .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                    .clipShape(.circle)
                    // Splits off the notch's right edge, like a droplet pulling away.
                    .transition(.scale(scale: 0.2, anchor: .leading).combined(with: .opacity).combined(with: .offset(x: -18)))
            }
        }
    }
}

/// What one circle shows: artwork, a status dot, or a ring.
@available(macOS 26, *)
private struct SatelliteContent: View {
    let kind: NotchViewModel.Activity
    let diameter: CGFloat

    @Environment(AgentMonitor.self) private var agents
    @Environment(DownloadMonitor.self) private var downloads
    @Environment(MusicManager.self) private var music

    private var ringSize: CGFloat { diameter - 10 }
    private static let downloadBlue = Color(red: 0.35, green: 0.65, blue: 1)

    var body: some View {
        switch kind {
        case .music:
            ArtworkView(image: music.artwork, size: diameter - 6, cornerRadius: (diameter - 6) / 2)
        case .agent:
            if let session = agents.sessionNeedingInput ?? agents.workingSessions.first {
                AgentStatusDot(kind: session.kind, state: session.state, size: 9)
            }
        case .download:
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(downloads.fraction ?? 0, 0.02))
                    .stroke(Self.downloadBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .black))
            }
            .frame(width: ringSize, height: ringSize)
        case .build:
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .phaseAnimator([0.0, 360.0]) { ring, angle in
                        ring.rotationEffect(.degrees(angle))
                    } animation: { _ in .linear(duration: 1) }
                Image(systemName: "hammer.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.blue)
            }
            .frame(width: ringSize, height: ringSize)
        default:
            EmptyView()
        }
    }
}

/// What a glass bead on the open Home tab shows. `regular` adds a label to `compact`.
@available(macOS 26, *)
struct GlassBeadContent: View {
    enum Style {
        case compact
        case regular
    }

    let kind: NotchViewModel.Activity
    let style: Style

    @Environment(AgentMonitor.self) private var agents
    @Environment(XcodeBuildMonitor.self) private var xcode
    @Environment(DownloadMonitor.self) private var downloads
    @Environment(MusicManager.self) private var music

    private var isCompact: Bool { style == .compact }

    var body: some View {
        HStack(spacing: isCompact ? 5 : 8) {
            switch kind {
            case .agent: agent
            case .build: build
            case .download: download
            case .music: nowPlaying
            default: EmptyView()
            }
        }
        .font(.system(size: isCompact ? 11 : 12, weight: .bold).monospacedDigit())
        .lineLimit(1)
    }

    @ViewBuilder
    private var agent: some View {
        if let session = agents.sessionNeedingInput ?? agents.workingSessions.first {
            AgentStatusDot(kind: session.kind, state: session.state, size: isCompact ? 7 : 8)
            if !isCompact {
                label(session.project)
            }
            if session.state == .needsInput {
                Text(isCompact ? "Input" : "Needs you")
                    .foregroundStyle(.orange)
            } else {
                elapsed(since: session.stateSince, tint: session.kind.tint)
            }
        }
    }

    @ViewBuilder
    private var build: some View {
        Image(systemName: "hammer.fill")
            .font(.system(size: isCompact ? 9 : 11, weight: .bold))
            .foregroundStyle(.blue)
        if !isCompact {
            label(xcode.buildingProject ?? "Building")
        }
        if let since = xcode.buildingSince {
            elapsed(since: since, tint: .blue)
        }
    }

    @ViewBuilder
    private var download: some View {
        DownloadClosedLeading()
            .scaleEffect(isCompact ? 0.8 : 1)
        if !isCompact {
            label(downloads.currentFileName ?? downloads.justFinished?.lastPathComponent ?? "Downloading")
        }
        DownloadClosedTrailing()
    }

    @ViewBuilder
    private var nowPlaying: some View {
        ArtworkView(image: music.artwork, size: isCompact ? 14 : 22, cornerRadius: isCompact ? 3 : 5)
        if !isCompact, let track = music.track {
            label(track.title)
        }
        AudioVisualizer(isPlaying: music.isPlaying, color: music.accentColor, height: isCompact ? 10 : 14)
            .frame(width: 22)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func elapsed(since: Date, tint: Color) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(context.date.timeIntervalSince(since).countdownText)
                .foregroundStyle(tint)
        }
    }
}
