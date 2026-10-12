import AppKit
import SwiftUI

/// Drives the notch: open/closed state, geometry, live activities, and hover handling.
@Observable
final class NotchViewModel {
    enum Status {
        case closed
        case open
    }

    enum Tab: String, CaseIterable, Identifiable {
        case home
        case reflect
        case dev
        case shelf

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .reflect: "Reflect"
            case .dev: "Dev"
            case .shelf: "Shelf"
            }
        }

        var symbol: String {
            switch self {
            case .home: "house.fill"
            case .reflect: "heart.text.square.fill"
            case .dev: "chevron.left.forwardslash.chevron.right"
            case .shelf: "tray.fill"
            }
        }
    }

    /// Compact content shown beside the physical notch while it's closed.
    enum Activity: Equatable {
        case none
        case music
        case charging
        case hud
        case alert
        case agent
        case build
        case charged
    }

    // MARK: Layout constants

    static let windowSize = CGSize(width: 780, height: 300)
    static let openContentSize = CGSize(width: 660, height: 172)
    static let lyricLineHeight: CGFloat = 22
    static let alertHeight: CGFloat = 52
    private static let alertMinWidth: CGFloat = 420

    private static let closedTopRadius: CGFloat = 6
    private static let openTopRadius: CGFloat = 19

    // MARK: State

    private(set) var status: Status = .closed
    private(set) var isHovering = false
    var tab: Tab = .home
    var isDropTargeted = false {
        didSet { if isDropTargeted { open(tab: .shelf) } }
    }

    private(set) var notchSize = CGSize(width: 185, height: 32)
    private(set) var hasPhysicalNotch = true
    private(set) var screenFrame: CGRect = .zero

    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var didClose: () -> Void = {}
    /// Keeps the notch open when the mouse leaves.
    @ObservationIgnored var isPinned = false
    /// True while a text field in the notch has focus, so typing isn't cut off by a stray mouse move.
    @ObservationIgnored var isEditingText = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let music: MusicManager
    @ObservationIgnored private let battery: BatteryManager
    @ObservationIgnored private let lyrics: LyricsManager
    @ObservationIgnored private let hud: HUDManager
    @ObservationIgnored private let alerts: AlertManager
    @ObservationIgnored private let agents: AgentMonitor
    @ObservationIgnored private let xcode: XcodeBuildMonitor
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?

    init(settings: AppSettings, music: MusicManager, battery: BatteryManager, lyrics: LyricsManager, hud: HUDManager, alerts: AlertManager,
         agents: AgentMonitor, xcode: XcodeBuildMonitor) {
        self.settings = settings
        self.music = music
        self.battery = battery
        self.lyrics = lyrics
        self.hud = hud
        self.alerts = alerts
        self.agents = agents
        self.xcode = xcode
    }

    // MARK: Geometry

    func configure(for screen: NSScreen) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
            hasPhysicalNotch = true
        } else {
            // No notch: draw a fake one the height of the menu bar.
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: 185, height: menuBarHeight > 0 ? menuBarHeight : 24)
            hasPhysicalNotch = false
        }
    }

    var activity: Activity {
        // Highest priority first: direct feedback, then things needing attention, then ambient status.
        if hud.visibleKind != nil && status == .closed { return .hud }
        if alerts.currentAlert != nil { return .alert }
        if xcode.freshResult != nil { return .build }
        if agents.justFinished != nil || agents.sessionNeedingInput != nil { return .agent }
        if battery.isShowingChargedActivity { return .charged }
        if settings.showChargingActivity && battery.isShowingChargingActivity { return .charging }
        if xcode.isBuilding { return .build }
        if settings.showMusicActivity && music.track != nil && music.isPlaying { return .music }
        if agents.isAnyWorking { return .agent }
        return .none
    }

    var wingWidth: CGFloat {
        switch activity {
        case .none: 0
        case .music: notchSize.height + 14
        case .charging: 72
        case .hud: 84
        case .alert: 64
        case .agent: 84
        case .build: 84
        case .charged: 96
        }
    }

    var showsLyricLine: Bool {
        activity == .music && settings.lyricsEnabled && settings.lyricsUnderNotch && lyrics.hasSyncedLyrics
    }

    var topRadius: CGFloat { status == .open ? Self.openTopRadius : Self.closedTopRadius }
    var bottomRadius: CGFloat {
        if status == .open || activity == .alert { return 24 }
        return showsLyricLine ? 14 : 10
    }

    var closedSize: CGSize {
        var size = CGSize(
            width: notchSize.width + wingWidth * 2 + Self.closedTopRadius * 2,
            height: notchSize.height + (showsLyricLine ? Self.lyricLineHeight : 0)
        )
        if activity == .alert {
            size.width = max(size.width, Self.alertMinWidth)
            size.height += Self.alertHeight
        }
        if isHovering {
            size.width += 14
            size.height += 4
        }
        return size
    }

    var openSize: CGSize {
        CGSize(
            width: Self.openContentSize.width + Self.openTopRadius * 2,
            height: notchSize.height + Self.openContentSize.height
        )
    }

    var currentSize: CGSize { status == .open ? openSize : closedSize }

    /// The notch's visible area in global screen coordinates, used for hit-testing the mouse.
    var hitRect: CGRect {
        let size = currentSize
        let rect = CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return status == .closed ? rect.insetBy(dx: -8, dy: -6) : rect
    }

    // MARK: Open / close

    func open(tab: Tab? = nil) {
        cancelPendingTasks()
        if let tab { self.tab = tab }
        guard status != .open else { return }

        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        withAnimation(.notchOpen) {
            status = .open
            isHovering = false
        }
    }

    func close() {
        cancelPendingTasks()
        guard status != .closed else { return }
        isDropTargeted = false
        withAnimation(.notchClose) {
            status = .closed
        }
        didClose()
    }

    func toggle() {
        status == .open ? close() : open()
    }

    // MARK: Mouse tracking

    /// Called for every mouse event and on a slow timer by the window controller.
    func handleMouse(at point: CGPoint, isDraggingFiles: Bool) {
        let inside = hitRect.contains(point)

        switch status {
        case .closed:
            guard inside else {
                hoverTask?.cancel()
                hoverTask = nil
                if isHovering { withAnimation(.notchPeek) { isHovering = false } }
                return
            }
            if isDraggingFiles {
                open(tab: .shelf)
                return
            }
            // The peek only hints that the notch is clickable. With open-on-hover it would be a
            // second resize right before the open animation, so skip it.
            if !settings.openOnHover && !isHovering { withAnimation(.notchPeek) { isHovering = true } }
            if settings.openOnHover && hoverTask == nil {
                let delay = settings.hoverDelay
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.open()
                }
            }

        case .open:
            if inside || isPinned || isEditingText || isDropTargeted || isDraggingFiles {
                closeTask?.cancel()
                closeTask = nil
            } else if closeTask == nil {
                closeTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    self?.close()
                }
            }
        }
    }

    private func cancelPendingTasks() {
        hoverTask?.cancel()
        hoverTask = nil
        closeTask?.cancel()
        closeTask = nil
    }

}
