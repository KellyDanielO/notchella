import Foundation

/// Owns every long-lived service and wires them together.
final class AppModel {
    let settings = AppSettings()
    let music = MusicManager()
    let lyrics = LyricsManager()
    let battery: BatteryManager
    let calendar = CalendarManager()
    let shelf = ShelfManager()
    let hud: HUDManager
    let alerts: AlertManager
    let reflect: ReflectStore
    let agents: AgentMonitor
    let xcode: XcodeBuildMonitor
    let headphones: HeadphonesManager
    let downloads: DownloadMonitor
    let idle: IdleManager
    let keepAwake = KeepAwakeManager()
    let devServers = DevServerScanner()
    let updates = UpdateManager()
    let notch: NotchViewModel

    private var keepAwakeTimer: Timer?

    init() {
        battery = BatteryManager(settings: settings)
        hud = HUDManager(settings: settings)
        alerts = AlertManager(settings: settings)
        reflect = ReflectStore()
        agents = AgentMonitor(settings: settings)
        xcode = XcodeBuildMonitor(settings: settings)
        headphones = HeadphonesManager(settings: settings)
        downloads = DownloadMonitor(settings: settings)
        idle = IdleManager(settings: settings, reflect: reflect)
        notch = NotchViewModel(
            settings: settings,
            music: music,
            battery: battery,
            lyrics: lyrics,
            hud: hud,
            alerts: alerts,
            agents: agents,
            xcode: xcode,
            headphones: headphones,
            downloads: downloads,
            idle: idle
        )

        // Ambient affirmations only drift in when they won't cover something more useful.
        idle.canShowAmbient = { [weak self] in
            guard let notch = self?.notch else { return false }
            return notch.status == .closed && [.none, .idle, .music].contains(notch.activity)
        }
        battery.onPluggedIn = { [weak self] in self?.idle.surprise() }

        music.onTrackChange = { [weak self] track in
            guard let self, settings.lyricsEnabled else { return }
            lyrics.load(for: track)
        }
    }

    func start() {
        music.start()
        battery.start()
        hud.start()
        alerts.start()
        agents.start()
        xcode.start()
        headphones.start()
        downloads.start()
        idle.start()

        updateKeepAwake()
        keepAwakeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateKeepAwake() }
        }
    }

    private func updateKeepAwake() {
        let shouldStayAwake = switch settings.keepAwakeMode {
        case .off: false
        case .always: true
        case .whileAgentsWork: agents.isAnyWorking
        }
        let projects = agents.workingSessions.map(\.project).joined(separator: ", ")
        keepAwake.update(
            keepAwake: shouldStayAwake,
            includeDisplay: settings.keepDisplayAwake,
            reason: projects.isEmpty ? "Notch: keep awake" : "Notch: agent working in \(projects)"
        )
    }
}
