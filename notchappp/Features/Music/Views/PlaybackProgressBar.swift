import SwiftUI

/// Scrubbable progress line; the playhead appears on hover.
struct PlaybackProgressBar: View {
    @Environment(MusicManager.self) private var music
    @State private var scrubPosition: TimeInterval?
    @State private var isHovered = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !music.isPlaying || scrubPosition != nil)) { context in
            let duration = max(music.track?.duration ?? 1, 1)
            let elapsed = scrubPosition ?? music.elapsed(at: context.date)
            let fraction = min(elapsed / duration, 1)
            let isActive = isHovered || scrubPosition != nil

            VStack(spacing: 3) {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule()
                            .fill(.white)
                            .frame(width: width * fraction)
                        Circle()
                            .fill(.white)
                            .frame(width: 11, height: 11)
                            .scaleEffect(isActive ? 1 : 0.01)
                            .offset(x: width * fraction - 5.5)
                    }
                    .frame(height: isActive ? 5 : 3.5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let position = min(max(value.location.x / width, 0), 1)
                                scrubPosition = position * duration
                            }
                            .onEnded { _ in
                                if let scrubPosition { music.seek(to: scrubPosition) }
                                scrubPosition = nil
                            }
                    )
                }
                .frame(height: 12)

                HStack {
                    Text(elapsed.playbackTimestamp)
                    Spacer()
                    Text("-" + max(duration - elapsed, 0).playbackTimestamp)
                }
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isActive)
        }
        .onHover { isHovered = $0 }
    }
}
