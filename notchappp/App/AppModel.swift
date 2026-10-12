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
    let keepAwake = KeepAwakeManager()
    let devServers = DevServerScanner()
    let notch: NotchViewModel

    private var keepAwakeTimer: Timer?

    init() {
        battery = BatteryManager(settings: settings)
        hud = HUDManager(settings: settings)
        alerts = AlertManager(settings: settings)
        reflect = ReflectStore()
        agents = AgentMonitor(settings: settings)
        xcode = XcodeBuildMonitor(settings: settings)
        notch = NotchViewModel(
            settings: settings,
            music: music,
            battery: battery,
            lyrics: lyrics,
            hud: hud,
            alerts: alerts,
            agents: agents,
            xcode: xcode
        )

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
