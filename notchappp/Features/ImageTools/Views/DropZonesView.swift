import SwiftUI

/// While files are dragged over the open notch, its pages give way to two targets:
/// keep the files on the Shelf, or send the images to the Images tab for editing.
struct DropZonesView: View {
    private enum Zone {
        case shelf
        case images
    }

    @Environment(NotchViewModel.self) private var notch
    @Environment(ShelfManager.self) private var shelf
    @Environment(ImageToolsManager.self) private var tools
    @State private var targeted: Zone?

    var body: some View {
        HStack(spacing: 12) {
            zone(.shelf, symbol: "tray.and.arrow.down.fill", title: "Shelf", subtitle: "Keep files close") { urls in
                shelf.add(urls)
                notch.tab = .shelf
            }
            zone(.images, symbol: "photo.on.rectangle.angled", title: "Edit images", subtitle: "Cut out, resize, convert") { urls in
                // Anything that isn't an image still lands somewhere useful.
                if tools.add(urls) {
                    notch.toolsPage = .images
                    notch.tab = .dev
                } else {
                    shelf.add(urls)
                    notch.tab = .shelf
                }
            }
        }
    }

    private func zone(
        _ zone: Zone,
        symbol: String,
        title: String,
        subtitle: String,
        onDrop: @escaping ([URL]) -> Void
    ) -> some View {
        let isTargeted = targeted == zone

        return VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .symbolEffect(.bounce, value: isTargeted)
            Text(title)
                .font(.system(size: 13, weight: .bold))
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isTargeted ? .white : .white.opacity(0.75))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .notchPanel()
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    .white.opacity(isTargeted ? 0.7 : 0.18),
                    style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [6, 5])
                )
        }
        .scaleEffect(isTargeted ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            onDrop(urls)
            return true
        } isTargeted: { isOver in
            // Keeps the notch open and accepting the drag while it's over a zone.
            notch.isDropTargeted = isOver || (targeted != nil && targeted != zone)
            if isOver {
                targeted = zone
            } else if targeted == zone {
                targeted = nil
            }
        }
    }
}
