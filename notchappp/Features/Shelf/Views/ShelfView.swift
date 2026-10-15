import QuickLookThumbnailing
import SwiftUI

/// Drop files on the notch to stash them, then drag them back out or AirDrop them.
struct ShelfView: View {
    @Environment(ShelfManager.self) private var shelf
    @Environment(NotchViewModel.self) private var notch

    var body: some View {
        content
            .animation(.smooth(duration: 0.2), value: notch.isDropTargeted)
    }

    @ViewBuilder
    private var content: some View {
        if shelf.items.isEmpty {
            dropZone
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(shelf.items.count == 1 ? "1 item" : "\(shelf.items.count) items")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    NotchIconButton(symbol: "airplayaudio", size: 12, tint: .secondary) {
                        shelf.airDrop(shelf.items)
                    }
                    .help("AirDrop all")
                    NotchIconButton(symbol: "trash", size: 12, tint: .secondary, action: shelf.removeAll)
                        .help("Clear shelf")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItemView(url: url)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                .white.opacity(notch.isDropTargeted ? 0.6 : 0.18),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolEffect(.bounce, value: notch.isDropTargeted)
                    Text(notch.isDropTargeted ? "Let go to keep it here" : "Drop files to stash them")
                        .font(.system(size: 12, weight: .semibold))
                        .contentTransition(.opacity)
                }
                .foregroundStyle(notch.isDropTargeted ? .white : .secondary)
            }
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
            .allowsHitTesting(false)
    }
}

private struct ShelfItemView: View {
    let url: URL

    @Environment(ShelfManager.self) private var shelf
    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            // A Quick Look preview of the file itself (images, PDFs, videos), or its Finder icon.
            Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: thumbnail == nil ? 0 : 6, style: .continuous))
                .frame(width: 48, height: 48)
                .task(id: url) { thumbnail = await Self.preview(of: url) }
            Text(url.lastPathComponent)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.1 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button { shelf.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(PressableButtonStyle())
                .help("Remove from Shelf")
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering in withAnimation(.smooth(duration: 0.15)) { isHovered = hovering } }
        .onTapGesture(count: 2) { shelf.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelf.open(url) }
            Button("Show in Finder") { shelf.revealInFinder(url) }
            Button("AirDrop") { shelf.airDrop([url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            Divider()
            Button("Remove from Shelf", role: .destructive) { shelf.remove(url) }
        }
        .help(url.path)
    }

    private static func preview(of url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 96, height: 96),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}
