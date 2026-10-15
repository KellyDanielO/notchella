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
            case .dev: "Tools"
            case .shelf: "Shelf"
            }
        }

        var symbol: String {
            switch self {
            case .home: "house.fill"
            case .reflect: "heart.text.square.fill"
            case .dev: "wrench.and.screwdriver.fill"
            case .shelf: "tray.fill"
            }
        }
    }

    /// The pages inside the Tools tab.
    enum ToolsPage: CaseIterable {
        case dev
        case images

        var title: String {
            switch self {
            case .dev: "Dev"
            case .images: "Images"
            }
        }

        var symbol: String {
            switch self {
            case .dev: "chevron.left.forwardslash.chevron.right"
            case .images: "photo.on.rectangle.angled"
            }
        }
    }

    /// Compact content shown beside the physical notch while it's closed.
    nonisolated enum Activity: Hashable, Sendable {
        case none
        case music
        case charging
        case hud
        case alert
        case agent
        case build
        case charged
        case headphones
        case download
        case breakNudge
        case affirmation
        /// The internet just dropped or came back.
        case network
        /// The battery just fell to 20% or 10% while unplugged.
        case lowBattery
        /// Nothing going on, but an idle style (eyes) is on.
        case idle
    }

    // MARK: Layout constants

    static let windowSize = CGSize(width: 780, height: 300)
    static let openContentSize = CGSize(width: 600, height: 172)
    static let lyricLineHeight: CGFloat = 22
    static let alertHeight: CGFloat = 52
    static let affirmationHeight: CGFloat = 44
    private static let alertMinWidth: CGFloat = 420
    /// The space between the ink bar and the glass cards, and between the cards themselves.
    static let glassGap: CGFloat = 10
    /// The space between the closed notch and the circles beside it, and between circles.
    static let satelliteGap: CGFloat = 6

    private static let closedTopRadius: CGFloat = 6
    private static let openTopRadius: CGFloat = 19

    // MARK: State

    private(set) var status: Status = .closed
    private(set) var isHovering = false
    var tab: Tab = .home {
        didSet { if status == .open { trackTabUsed() } }
    }
    var toolsPage: ToolsPage = .dev
    var isDropTargeted = false {
        didSet { if isDropTargeted { open() } }
    }
    /// Files are being dragged from elsewhere. The open notch swaps its page for drop zones.
    private(set) var isDraggingFiles = false

    private(set) var notchSize = CGSize(width: 185, height: 32)
    private(set) var hasPhysicalNotch = true
    private(set) var screenFrame: CGRect = .zero
    /// The cursor, tracked only while the idle eyes are showing (they follow it).
    private(set) var mouseLocation: CGPoint = .zero

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
    @ObservationIgnored private let headphones: HeadphonesManager
    @ObservationIgnored private let downloads: DownloadMonitor
    @ObservationIgnored private let idle: IdleManager
    @ObservationIgnored private let menuBar: MenuBarSpace
    @ObservationIgnored private let network: NetworkMonitor
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private var dragEndTask: Task<Void, Never>?
    /// The drop zones stay up this long after the button is released, because macOS hands the
    /// drop over a moment after mouse-up. Hiding them at once removed the target mid-drop.
    private static let dragEndGrace: Duration = .milliseconds(800)

    init(settings: AppSettings, music: MusicManager, battery: BatteryManager, lyrics: LyricsManager, hud: HUDManager, alerts: AlertManager,
         agents: AgentMonitor, xcode: XcodeBuildMonitor, headphones: HeadphonesManager,
         downloads: DownloadMonitor, idle: IdleManager, menuBar: MenuBarSpace, network: NetworkMonitor) {
        self.settings = settings
        self.music = music
        self.battery = battery
        self.lyrics = lyrics
        self.hud = hud
        self.alerts = alerts
        self.agents = agents
        self.xcode = xcode
        self.headphones = headphones
        self.downloads = downloads
        self.idle = idle
        self.menuBar = menuBar
        self.network = network
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
        menuBar.configure(
            screen: screen.frame,
            notch: CGRect(x: screen.frame.midX - notchSize.width / 2, y: screen.frame.maxY - notchSize.height,
                          width: notchSize.width, height: notchSize.height)
        )
    }

    var activity: Activity {
        // Highest priority first: direct feedback, then things needing attention, then ambient status.
        if hud.visibleKind != nil && status == .closed { return .hud }
        if alerts.currentAlert != nil { return .alert }
        if battery.lowBatteryWarning != nil && status == .closed { return .lowBattery }
        if xcode.freshResult != nil { return .build }
        if agents.justFinished != nil || agents.sessionNeedingInput != nil { return .agent }
        if agents.breakNudgeMinutes != nil { return .breakNudge }
        if headphones.isShowingActivity { return .headphones }
        if network.isShowingActivity { return .network }
        if battery.isShowingChargedActivity { return .charged }
        if settings.showChargingActivity && battery.isShowingChargingActivity { return .charging }
        if downloads.justFinished != nil && downloads.isShowingActivity { return .download }
        if idle.ambientAffirmation != nil && status == .closed && hasRoomForAffirmation { return .affirmation }
        // Ongoing and ambient states last for minutes, so they give way to the menu bar: rather than
        // sit on an app's menus or a menu bar icon, the notch shrinks back to the camera housing.
        if downloads.isShowingActivity && fitsBesideMenus(.download) { return .download }
        if xcode.isBuilding && fitsBesideMenus(.build) { return .build }
        if settings.showMusicActivity && music.track != nil && music.isPlaying && fitsBesideMenus(.music) { return .music }
        if agents.isAnyWorking && fitsBesideMenus(.agent) { return .agent }
        if settings.idleEyes && fitsBesideMenus(.idle) { return .idle }
        return .none
    }

    /// The menu bar left free on the tighter side of the notch, before the wings would cover the
    /// frontmost app's menus or a menu bar icon.
    private var menuBarRoom: (left: CGFloat, right: CGFloat) {
        let notchMinX = screenFrame.midX - notchSize.width / 2
        let notchMaxX = screenFrame.midX + notchSize.width / 2
        return (
            left: menuBar.leftItemsMaxX.map { notchMinX - $0 } ?? .infinity,
            right: menuBar.rightItemsMinX.map { $0 - notchMaxX } ?? .infinity
        )
    }

    /// Affirmations drop down as a wide card, which would hide most of an app's menus.
    var hasRoomForAffirmation: Bool {
        let room = menuBarRoom
        return (Self.alertMinWidth - notchSize.width) / 2 <= min(room.left, room.right)
    }

    private func fitsBesideMenus(_ activity: Activity) -> Bool {
        guard status == .closed else { return true }
        let room = menuBarRoom
        return wingWidth(for: activity) + Self.closedTopRadius <= min(room.left, room.right)
    }

    /// Activities that keep running for a while, in the same priority order `activity` uses.
    private var ongoingActivities: [Activity] {
        var ongoing: [Activity] = []
        if agents.sessionNeedingInput != nil { ongoing.append(.agent) }
        if settings.downloadsActivity && downloads.fraction != nil { ongoing.append(.download) }
        if xcode.isBuilding { ongoing.append(.build) }
        if settings.showMusicActivity && music.track != nil && music.isPlaying { ongoing.append(.music) }
        if agents.sessionNeedingInput == nil && agents.isAnyWorking { ongoing.append(.agent) }
        return ongoing
    }

    /// Small circles beside the closed notch, in the glass layout only, like the Dynamic Island's
    /// second activity: whatever is running besides the activity holding the wings.
    var closedBeads: [Activity] {
        guard usesGlassLayout, status == .closed else { return [] }
        let ongoing = ongoingActivities.filter(fitsBesideMenus)
        if activity == .alert || activity == .affirmation || activity == .lowBattery { return [] }

        // A brief activity (volume, a finished build…) borrows the wings from the top ongoing one,
        // which takes them back afterwards. Leave it out so it doesn't flash up as a bead.
        let displacedCount = ongoing.contains(activity) ? 0 : 1
        let beads = Array(ongoing.filter { $0 != activity }.dropFirst(displacedCount).prefix(2))
        // The circles trail off to the right, so they need room on that side as well.
        let reach = wingWidth + Self.closedTopRadius + CGFloat(beads.count) * (Self.satelliteGap + satelliteDiameter)
        return reach <= menuBarRoom.right ? beads : []
    }

    /// A circle as tall as the notch, less a little breathing room.
    var satelliteDiameter: CGFloat { notchSize.height - 4 }

    /// How far the circles reach past the notch's right edge.
    private var satellitesWidth: CGFloat {
        CGFloat(closedBeads.count) * (Self.satelliteGap + satelliteDiameter)
    }

    /// Wings hug their content: a glyph and a short readout (a timer, a percentage) take the
    /// compact width, and only wordier states, like a build result or a project name, get more.
    private static let compactWingWidth: CGFloat = 52

    var wingWidth: CGFloat { wingWidth(for: activity) }

    private func wingWidth(for activity: Activity) -> CGFloat {
        switch activity {
        case .none: 0
        case .music: notchSize.height + 14
        case .charging: 56
        case .hud: 84
        case .alert: 64
        case .agent:
            if agents.justFinished != nil { 84 }
            else if agents.sessionNeedingInput == nil && agents.workingSessions.count > 1 { 68 }
            else { Self.compactWingWidth }
        case .build: xcode.freshResult != nil ? 84 : Self.compactWingWidth
        case .charged: 96
        case .headphones: (headphones.device?.hasSeparateBuds ?? false) ? 96 : 72
        case .download: Self.compactWingWidth
        case .breakNudge: 96
        case .affirmation: 0
        case .network: 64
        case .lowBattery: 64
        case .idle: notchSize.height - 6
        }
    }

    var showsLyricLine: Bool {
        activity == .music && settings.lyricsEnabled && settings.lyricsUnderNotch && lyrics.hasSyncedLyrics
    }

    /// The liquid glass layout: only the header stays black ink; the pages hang below it as glass cards.
    var usesGlassLayout: Bool {
        guard settings.glassDesign else { return false }
        if #available(macOS 26, *) { return true }
        return false
    }

    private var isGlassOpen: Bool { status == .open && usesGlassLayout }

    var topRadius: CGFloat { status == .open ? Self.openTopRadius : Self.closedTopRadius }
    var bottomRadius: CGFloat {
        if isGlassOpen { return 16 }
        if status == .open || activity == .alert || activity == .affirmation || activity == .lowBattery { return 24 }
        return showsLyricLine ? 14 : 10
    }

    var closedSize: CGSize {
        var size = CGSize(
            width: notchSize.width + wingWidth * 2 + Self.closedTopRadius * 2,
            height: notchSize.height + (showsLyricLine ? Self.lyricLineHeight : 0)
        )
        if activity == .alert || activity == .lowBattery {
            size.width = max(size.width, Self.alertMinWidth)
            size.height += Self.alertHeight
        } else if activity == .affirmation {
            size.width = max(size.width, Self.alertMinWidth)
            size.height += Self.affirmationHeight
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

    /// The black shape's size. In the glass layout it shrinks to a bar holding just the header.
    var inkSize: CGSize {
        isGlassOpen ? CGSize(width: openSize.width, height: notchSize.height + 4) : currentSize
    }

    /// The area below the ink bar that the glass cards fill. It stays inside `openSize`,
    /// so hover tracking and hit-testing work unchanged.
    var glassCardsSize: CGSize {
        CGSize(
            width: Self.openContentSize.width,
            height: openSize.height - inkSize.height - Self.glassGap
        )
    }

    /// The notch's visible area in global screen coordinates, used for hit-testing the mouse.
    var hitRect: CGRect {
        let size = currentSize
        var rect = CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if status == .closed {
            // Hovering a circle beside the notch opens it too.
            rect.size.width += satellitesWidth
            // A file drag opens the notch from further away, so the drop zones open before the
            // cursor reaches the top edge, where pausing makes macOS bring up Mission Control.
            if isDraggingFiles { return rect.insetBy(dx: -60, dy: -70) }
        }
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
        trackTabUsed()
    }

    /// Counts which tabs get used, once per tab per day.
    private func trackTabUsed() {
        Analytics.trackDaily("tab_used", with: ["tab": tab.rawValue])
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
        updateDragging(isDraggingFiles)
        let inside = hitRect.contains(point)
        if activity == .idle && status == .closed && point != mouseLocation {
            mouseLocation = point
        }

        switch status {
        case .closed:
            guard inside else {
                hoverTask?.cancel()
                hoverTask = nil
                if isHovering { withAnimation(.notchPeek) { isHovering = false } }
                return
            }
            if isDraggingFiles {
                open()
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

    private func updateDragging(_ dragging: Bool) {
        if dragging {
            dragEndTask?.cancel()
            dragEndTask = nil
            guard !isDraggingFiles else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isDraggingFiles = true }
        } else if isDraggingFiles && dragEndTask == nil {
            dragEndTask = Task { [weak self] in
                try? await Task.sleep(for: Self.dragEndGrace)
                guard let self, !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { self.isDraggingFiles = false }
                dragEndTask = nil
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
