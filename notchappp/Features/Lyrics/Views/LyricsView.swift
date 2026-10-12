import Combine
import SwiftUI

/// Lyrics panel shown next to the player when the lyrics toggle is on.
struct LyricsView: View {
    @Environment(MusicManager.self) private var music
    @Environment(LyricsManager.self) private var lyrics

    var body: some View {
        Group {
            switch lyrics.state {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
            case .loaded(.synced(let lines)):
                SyncedLyricsView(lines: lines)
            case .loaded(.plain(let text)):
                ScrollView(showsIndicators: false) {
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            case .loaded(.instrumental):
                placeholder(symbol: "pianokeys", title: "Instrumental")
            case .loaded(.notFound):
                placeholder(symbol: "text.page.slash", title: "No lyrics found")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: music.track?.id) { lyrics.load(for: music.track) }
    }

    private func placeholder(symbol: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SyncedLyricsView: View {
    let lines: [LyricLine]

    @Environment(MusicManager.self) private var music
    @State private var currentID: Int?

    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lines) { line in
                        let isCurrent = line.id == currentID
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.28))
                            .scaleEffect(isCurrent ? 1 : 0.94, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture { music.seek(to: line.time) }
                    }
                }
                .padding(.vertical, 60)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.25),
                        .init(color: .black, location: 0.75),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear { sync(proxy, animated: false) }
            .onReceive(ticker) { _ in sync(proxy, animated: true) }
        }
    }

    private func sync(_ proxy: ScrollViewProxy, animated: Bool) {
        let index = LRCParser.index(in: lines, at: music.elapsed() + LyricsManager.leadTime)
        let id = index.map { lines[$0].id }
        guard id != currentID else { return }

        withAnimation(animated ? .smooth(duration: 0.45) : nil) {
            currentID = id
            proxy.scrollTo(id ?? lines.first?.id, anchor: .center)
        }
    }
}

/// The single current line shown under the closed notch.
struct ClosedLyricLineView: View {
    @Environment(MusicManager.self) private var music
    @Environment(LyricsManager.self) private var lyrics

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let line = lyrics.line(at: music.elapsed(at: context.date))
            ZStack {
                Text(line.map { $0.text.isEmpty ? "♪" : $0.text } ?? "♪")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(music.accentColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(line?.id)
                    .transition(.push(from: .bottom).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.35), value: line?.id)
        }
        .clipped()
    }
}
