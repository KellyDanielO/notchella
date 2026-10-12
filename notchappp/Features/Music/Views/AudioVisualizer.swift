import SwiftUI

/// A flowing waveform made of layered sine waves. It flattens to a calm line when paused.
struct AudioVisualizer: View {
    let isPlaying: Bool
    var color: Color = .white
    var height: CGFloat = 16

    @State private var energy: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: !isPlaying && energy == 0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let layers: [(speed: Double, frequency: Double, amplitude: CGFloat, opacity: Double)] = [
                    (3.2, 2.2, 1.0, 1.0),
                    (-2.1, 3.1, 0.7, 0.45),
                    (4.4, 1.4, 0.5, 0.25),
                ]
                for layer in layers {
                    let path = wave(in: size, time: time, speed: layer.speed, frequency: layer.frequency, amplitude: layer.amplitude)
                    canvas.stroke(path, with: .color(color.opacity(layer.opacity)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }
        }
        .frame(height: height)
        .onAppear { energy = isPlaying ? 1 : 0 }
        .onChange(of: isPlaying) { _, playing in
            withAnimation(.smooth(duration: 0.6)) { energy = playing ? 1 : 0 }
        }
    }

    private func wave(in size: CGSize, time: TimeInterval, speed: Double, frequency: Double, amplitude: CGFloat) -> Path {
        var path = Path()
        let midY = size.height / 2
        let steps = 40
        // A slow "breathing" envelope makes the wave feel like it's reacting to the music.
        let pulse = 0.55 + 0.45 * abs(sin(time * 1.7))
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            // Taper the ends so the wave fades into the notch edges.
            let taper = sin(progress * .pi)
            let y = sin(progress * .pi * 2 * frequency + time * speed) * taper * pulse
            let point = CGPoint(
                x: size.width * progress,
                y: midY + CGFloat(y) * midY * amplitude * max(energy, 0.08)
            )
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}
