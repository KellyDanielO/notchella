import SwiftUI

/// Left wing: a progress ring while downloading, a check when done.
struct DownloadClosedLeading: View {
    @Environment(DownloadMonitor.self) private var downloads

    var body: some View {
        Group {
            if downloads.justFinished != nil && downloads.fraction == nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
            } else {
                ZStack {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(downloads.fraction ?? 0, 0.02))
                        .stroke(Color(red: 0.35, green: 0.65, blue: 1), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "arrow.down")
                        .font(.system(size: 7, weight: .black))
                }
                .frame(width: 16, height: 16)
            }
        }
        .help(downloads.currentFileName ?? downloads.justFinished?.lastPathComponent ?? "Download")
    }
}

/// Right wing: the percentage, or "Done" (click to reveal in Finder).
struct DownloadClosedTrailing: View {
    @Environment(DownloadMonitor.self) private var downloads

    var body: some View {
        Group {
            if let fraction = downloads.fraction {
                Text("\(Int((fraction * 100).rounded()))%")
                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1))
                    .contentTransition(.numericText())
            } else if downloads.justFinished != nil {
                Text("Done")
                    .foregroundStyle(.green)
            }
        }
        .font(.system(size: 12, weight: .bold).monospacedDigit())
    }
}
