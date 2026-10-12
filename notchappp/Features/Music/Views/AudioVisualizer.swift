import SwiftUI

/// Five rounded bars that bounce while music plays, like the bars in the app icon.
/// Pausing eases them down into a row of dots; resuming eases them back up.
struct AudioVisualizer: View {
    let isPlaying: Bool
    var color: Color = .white
    var height: CGFloat = 16

    private static let barWidth: CGFloat = 3
    private static let barGap: CGFloat = 2.5
    private static let settleDuration: TimeInterval = 0.5

    /// Per bar: how tall it can get, and two incommensurate speeds so the motion never visibly repeats.
    private static let bars: [(reach: Double, speedA: Double, speedB: Double, phase: Double)] = [
        (0.60, 6.1, 9.7, 0.0),
        (0.90, 7.4, 4.3, 1.3),
        (0.75, 5.3, 11.2, 2.9),
        (1.00, 8.2, 6.6, 4.1),
        (0.65, 6.7, 8.9, 5.6),
    ]

    /// `level` runs from 0 (paused, dots) to 1 (playing). It's computed per frame from the last
    /// change rather than animated, because a Canvas can't interpolate state on its own.
    @State private var change = (from: 0.0, to: 0.0, start: Date.distantPast)
    @State private var isSettling = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !isPlaying && !isSettling)) { context in
            let date = context.date
            let level = level(at: date)
            let time = date.timeIntervalSinceReferenceDate

            Canvas { canvas, size in
                let count = CGFloat(Self.bars.count)
                let totalWidth = count * Self.barWidth + (count - 1) * Self.barGap
                var x = (size.width - totalWidth) / 2
                let maxHeight = size.height

                for bar in Self.bars {
                    // Two sines per bar, mapped to 0...1: smooth, organic bouncing.
                    let motion = 0.5 + 0.3 * sin(time * bar.speedA + bar.phase) + 0.2 * sin(time * bar.speedB + bar.phase * 1.7)
                    let playingHeight = maxHeight * bar.reach * (0.42 + 0.58 * motion)
                    let barHeight = Self.barWidth + (playingHeight - Self.barWidth) * level
                    let rect = CGRect(x: x, y: (maxHeight - barHeight) / 2, width: Self.barWidth, height: barHeight)
                    canvas.fill(
                        Path(roundedRect: rect, cornerRadius: Self.barWidth / 2),
                        with: .color(color.opacity(0.55 + 0.45 * level))
                    )
                    x += Self.barWidth + Self.barGap
                }
            }
        }
        .frame(height: height)
        .onAppear {
            let level = isPlaying ? 1.0 : 0.0
            change = (level, level, .now)
        }
        .onChange(of: isPlaying) { _, playing in
            let now = Date.now
            change = (level(at: now), playing ? 1 : 0, now)
        }
        // Keep the timeline running until a pause has finished settling, then let it stop.
        .task(id: change.start) {
            isSettling = true
            do {
                try await Task.sleep(for: .seconds(Self.settleDuration + 0.05))
            } catch {
                return
            }
            isSettling = false
        }
    }

    private func level(at date: Date) -> Double {
        let progress = min(max(date.timeIntervalSince(change.start) / Self.settleDuration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        return change.from + (change.to - change.from) * eased
    }
}
