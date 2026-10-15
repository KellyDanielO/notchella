import SwiftUI

/// The Images page: a tray of dropped images and the recipe, or a large before/after preview.
struct ImageToolsView: View {
    @Environment(ImageToolsManager.self) private var tools

    var body: some View {
        ZStack {
            if let id = tools.previewedID, tools.items.contains(where: { $0.id == id }) {
                ComparePreview(id: id)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .notchPanel()
                    .transition(.blurFade.combined(with: .scale(scale: 0.96)))
            } else {
                HStack(spacing: 12) {
                    ImageTray()
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .notchPanel()
                    RecipeCard()
                        .padding(10)
                        .frame(width: 252)
                        .frame(maxHeight: .infinity)
                        .notchPanel()
                }
                .transition(.blurFade.combined(with: .scale(scale: 1.03)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: tools.previewedID)
        .dropDestination(for: URL.self) { urls, _ in tools.add(urls) }
    }
}

// MARK: Tray

private struct ImageTray: View {
    @Environment(ImageToolsManager.self) private var tools

    var body: some View {
        if tools.items.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Text(summary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                    NotchIconButton(symbol: "trash", size: 11, tint: .secondary, action: tools.clear)
                        .help("Clear")
                }
                .frame(height: 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tools.items) { item in
                            ImageTile(item: item)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var summary: String {
        let count = tools.items.count
        let images = count == 1 ? "1 image" : "\(count) images"
        if tools.isRendering { return "\(images) · previewing" }
        if tools.failedCount > 0 { return "\(images) · \(tools.failedCount) failed" }
        if tools.savedCount == count { return "\(images) · saved" }
        return "\(images) · tap one to compare"
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 24, weight: .semibold))
            Text("Drop images to edit")
                .font(.system(size: 13, weight: .bold))
            Text("Cut out backgrounds, resize and convert,\nall on your Mac.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
    }
}

/// One image: its result (or the original, until there is one) on a transparency checkerboard.
private struct ImageTile: View {
    let item: ImageToolsManager.Item

    @Environment(ImageToolsManager.self) private var tools
    @State private var isHovered = false

    private static let side: CGFloat = 92

    var body: some View {
        ZStack {
            Checkerboard()
            if let image = item.result ?? item.original {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(item.result == nil ? 0 : 6)
                    .transition(.blurFade)
                    .id(item.result == nil ? 0 : 1)
            }
            StateOverlay(state: item.state)
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(isHovered ? 0.5 : (item.hasResult ? 0.3 : 0.1)), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button { tools.remove(item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(PressableButtonStyle())
                .padding(5)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(isHovered ? 1.04 : 1)
        .onHover { hovering in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isHovered = hovering } }
        .onTapGesture { tools.previewedID = item.id }
        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
        .help(helpText)
    }

    private var helpText: String {
        switch item.state {
        case .failed(let message): "\(item.source.lastPathComponent): \(message)"
        case .saved(let url): "Saved as \(url.lastPathComponent)"
        default: "\(item.source.lastPathComponent). Click to compare, or drag the result out."
        }
    }
}

/// What's happening to an image, drawn over it: a scanning light while it renders,
/// a badge once it's done, a warning if it failed.
private struct StateOverlay: View {
    let state: ImageToolsManager.Item.State
    var badgeSize: CGFloat = 15

    var body: some View {
        switch state {
        case .waiting:
            EmptyView()
        case .working:
            ZStack {
                Color.black.opacity(0.35)
                ScanSweep()
            }
            .transition(.opacity)
        case .ready:
            EmptyView()
        case .saved:
            badge("checkmark.circle.fill", .green)
        case .failed:
            ZStack {
                Color.black.opacity(0.45)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: badgeSize + 3, weight: .bold))
                    .foregroundStyle(.orange)
            }
            .transition(.opacity)
        }
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: badgeSize, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(5)
            .transition(.scale(scale: 0.3).combined(with: .opacity))
    }
}

// MARK: Before / after

/// The original and the result side by side, larger, with arrows to step through the batch.
private struct ComparePreview: View {
    let id: ImageToolsManager.Item.ID

    @Environment(ImageToolsManager.self) private var tools
    @State private var largeOriginal: NSImage?
    @State private var largeResult: NSImage?

    private var index: Int? { tools.items.firstIndex { $0.id == id } }
    private var item: ImageToolsManager.Item? { index.map { tools.items[$0] } }

    var body: some View {
        if let item, let index {
            HStack(spacing: 8) {
                pane(image: largeOriginal ?? item.original, label: "Before", state: .waiting)
                pane(image: largeResult ?? item.result, label: "After", state: item.state)
                controls(index: index, item: item)
            }
            // Sharper versions than the tray's thumbnails, loaded for whichever image is open.
            .task(id: item.fileURL) {
                largeOriginal = await Self.load(item.source)
                largeResult = item.hasResult ? await Self.load(item.fileURL) : nil
            }
        }
    }

    private func pane(image: NSImage?, label: String, state: ImageToolsManager.Item.State) -> some View {
        ZStack(alignment: .bottomLeading) {
            Checkerboard()
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.blurFade)
                    .id(image)
            }
            StateOverlay(state: state, badgeSize: 18)
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func controls(index: Int, item: ImageToolsManager.Item) -> some View {
        VStack(spacing: 4) {
            NotchIconButton(symbol: "xmark", size: 11, tint: .white.opacity(0.8)) { tools.previewedID = nil }
                .help("Back to the batch")
            Spacer(minLength: 0)
            NotchIconButton(symbol: "chevron.up", size: 11, tint: .white.opacity(index > 0 ? 0.8 : 0.25)) { step(-1, from: index) }
            Text("\(index + 1)/\(tools.items.count)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            NotchIconButton(symbol: "chevron.down", size: 11, tint: .white.opacity(index < tools.items.count - 1 ? 0.8 : 0.25)) { step(1, from: index) }
            Spacer(minLength: 0)
            NotchIconButton(symbol: "arrow.up.forward.app", size: 11, tint: .white.opacity(0.8)) {
                NSWorkspace.shared.open(item.fileURL)
            }
            .help("Open")
        }
        .frame(width: 30)
    }

    private func step(_ offset: Int, from index: Int) {
        let target = index + offset
        guard tools.items.indices.contains(target) else { return }
        tools.previewedID = tools.items[target].id
    }

    private static func load(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            ImageProcessor.thumbnail(of: url, maxPixelSize: 900).map { NSImage(cgImage: $0, size: .zero) }
        }.value
    }
}

// MARK: Shared pieces

/// The grey-and-darker grid editors use to show transparency.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 8
            for row in 0..<Int(ceil(size.height / square)) {
                for column in 0..<Int(ceil(size.width / square)) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)
                    context.fill(Path(rect), with: .color(.white.opacity(0.07)))
                }
            }
        }
        .background(.white.opacity(0.03))
    }
}

/// A band of light that sweeps down an image while it's being processed, like a scanner.
private struct ScanSweep: View {
    var body: some View {
        GeometryReader { geometry in
            let band = geometry.size.height * 0.4
            LinearGradient(colors: [.clear, .white.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: band)
                .phaseAnimator([false, true]) { view, isDown in
                    view.offset(y: isDown ? geometry.size.height : -band)
                } animation: { _ in .easeInOut(duration: 1.1) }
        }
        .allowsHitTesting(false)
    }
}

// MARK: Recipe

private struct RecipeCard: View {
    @Environment(ImageToolsManager.self) private var tools

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            options
            Spacer(minLength: 8)
            SaveButton()
        }
    }

    private var options: some View {
        @Bindable var tools = tools

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { tools.removeBackground.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.and.background.dotted")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Remove background")
                        .font(.system(size: 12, weight: .bold))
                    Spacer(minLength: 0)
                    Image(systemName: tools.removeBackground ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(tools.removeBackground ? .black : .white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(tools.removeBackground ? .white : .white.opacity(0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())

            OptionRow(label: "Size", options: ImageEditOptions.Size.allCases, selection: $tools.size) { size in
                size == .original ? "Full" : size == .half ? "½" : size.title
            }
            OptionRow(label: "Format", options: ImageEditOptions.Format.allCases, selection: $tools.format) { $0.title }
        }
    }
}

/// A label and a row of chips; the selected chip slides between options.
private struct OptionRow<Option: Hashable>: View {
    let label: String
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    @Namespace private var chip

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    let isSelected = option == selection
                    Text(title(option))
                        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background {
                            if isSelected {
                                Capsule().fill(.white).matchedGeometryEffect(id: "chip", in: chip)
                            }
                        }
                        .contentShape(Capsule())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selection = option }
                        }
                }
            }
            .padding(2)
            .background(Capsule().fill(.white.opacity(0.08)))
        }
    }
}

/// Shows previews rendering (progress fills the button), then saves to Downloads,
/// then opens the saved files.
private struct SaveButton: View {
    @Environment(ImageToolsManager.self) private var tools

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(tools.isRendering ? 0.12 : (isActive ? 1 : 0.1)))
                if tools.isRendering {
                    // Two copies of the label: white over the empty track, and black clipped to
                    // the fill, so the count stays legible as the progress passes under it.
                    label.foregroundStyle(.white)
                    Capsule()
                        .fill(.white)
                        .overlay { label.foregroundStyle(.black) }
                        .mask(alignment: .leading) {
                            GeometryReader { geometry in
                                Capsule().frame(width: max(geometry.size.height, geometry.size.width * tools.renderProgress))
                            }
                        }
                } else {
                    label.foregroundStyle(isActive ? .black : .white.opacity(0.5))
                }
            }
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .allowsHitTesting(!tools.isRendering)
        .animation(.smooth(duration: 0.3), value: tools.renderProgress)
        .animation(.smooth(duration: 0.3), value: tools.isRendering)
    }

    private enum Step {
        case empty
        case rendering
        case save
        case retry
        case reveal
    }

    private var step: Step {
        if tools.items.isEmpty { return .empty }
        if tools.isRendering { return .rendering }
        if tools.readyCount > 0 { return .save }
        if tools.failedCount > 0 && tools.savedCount == 0 { return .retry }
        return .reveal
    }

    private var isActive: Bool { step != .empty }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private var icon: String {
        switch step {
        case .empty, .save: "square.and.arrow.down.fill"
        case .rendering: "hourglass"
        case .retry: "arrow.clockwise"
        case .reveal: "folder.fill"
        }
    }

    private var title: String {
        switch step {
        case .empty: "Save"
        case .rendering: "Previewing \(tools.settledCount) of \(tools.items.count)"
        case .save: tools.readyCount == 1 ? "Save 1 to Downloads" : "Save \(tools.readyCount) to Downloads"
        case .retry: "Retry \(tools.failedCount) failed"
        case .reveal: "Show in Finder"
        }
    }

    private func action() {
        switch step {
        case .empty, .rendering: break
        case .save: tools.save()
        case .retry: tools.retryFailed()
        case .reveal: tools.revealSaved()
        }
    }
}
