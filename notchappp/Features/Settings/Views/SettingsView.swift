import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CalendarManager.self) private var calendar
    @Environment(HUDManager.self) private var hud
    @Environment(AlertManager.self) private var alerts
    @Environment(AgentMonitor.self) private var agents
    @Environment(IdleManager.self) private var idle
    @Environment(UpdateManager.self) private var updates
    @State private var hookError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Open on hover", isOn: $settings.openOnHover)
                if settings.openOnHover {
                    LabeledContent("Hover delay") {
                        HStack {
                            Slider(value: $settings.hoverDelay, in: 0...0.6, step: 0.05)
                            Text("\(settings.hoverDelay, specifier: "%.2f")s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                if #available(macOS 26, *) {
                    Toggle("Liquid glass design", isOn: $settings.glassDesign)
                }
            }

            Section {
                Toggle("Breathing glow", isOn: $settings.idleBreathingGlow)
                Toggle("Eyes", isOn: $settings.idleEyes)
                Toggle("Ambient affirmations", isOn: $settings.ambientAffirmations)
                if settings.ambientAffirmations {
                    Picker("Show one every", selection: $settings.ambientAffirmationMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("Hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                    LabeledContent("Preview") {
                        Button("Show one now", action: idle.showAmbientAffirmationNow)
                    }
                }
            } header: {
                Text("When idle")
            } footer: {
                Text("Mix and match. The glow pulses softly in the last song's colour; the eyes follow your cursor, blink, get sleepy after 11pm and jump when you plug in; affirmations come from your Reflect tab.")
                    .foregroundStyle(.secondary)
            }

            Section("Live activities") {
                Toggle("Now playing", isOn: $settings.showMusicActivity)
                Toggle("Charging", isOn: $settings.showChargingActivity)
                Toggle("Headphones & earbuds", isOn: $settings.headphonesActivity)
                Toggle("Downloads", isOn: $settings.downloadsActivity)
                Toggle("Tell me when the battery is charged", isOn: $settings.fullChargeAlert)
                if settings.fullChargeAlert {
                    Picker("Charged at", selection: $settings.fullChargeTarget) {
                        ForEach([80, 85, 90, 95, 100], id: \.self) { Text("\($0)%").tag($0) }
                    }
                }
            }

            Section {
                Toggle("Show Xcode build status", isOn: $settings.xcodeBuildStatusEnabled)
                Toggle("Play a sound when a build fails", isOn: $settings.buildFailureSound)
                    .disabled(!settings.xcodeBuildStatusEnabled)
            } header: {
                Text("Xcode")
            } footer: {
                Text("Works with Xcode and xcodebuild, no setup needed. Results come from Xcode's build logs in DerivedData.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Keep Mac awake", selection: $settings.keepAwakeMode) {
                    ForEach(KeepAwakeManager.Mode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Keep the display on too", isOn: $settings.keepDisplayAwake)
                    .disabled(settings.keepAwakeMode == .off)
                Toggle("Alert me when an agent finishes", isOn: $settings.agentFinishAlerts)
                Toggle("Nudge me to take breaks", isOn: $settings.agentBreakNudge)
                if settings.agentBreakNudge {
                    Stepper("After \(settings.agentBreakMinutes) minutes of agent work", value: $settings.agentBreakMinutes, in: 10...120, step: 5)
                }
                hookRow(.claude)
                hookRow(.codex)
                if let hookError {
                    Text(hookError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Agents & Sleep")
            } footer: {
                Text("Hooks report exactly when an agent is working, waiting for you, or done. Without them, Notch guesses from the agent's CPU use. Keep-awake stops idle sleep only: closing the lid still sleeps the Mac unless it's plugged in with an external display.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Replace system volume & brightness HUD", isOn: $settings.replaceSystemHUD)
                    .onChange(of: settings.replaceSystemHUD) { _, enabled in
                        if enabled { hud.start() }
                    }
            } header: {
                Text("Volume & Brightness")
            } footer: {
                Text("Hold Option+Shift for finer steps. External displays keep the system HUD.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Alert me about matching notifications", isOn: $settings.notificationAlertsEnabled)
                    .onChange(of: settings.notificationAlertsEnabled) { _, _ in alerts.start() }
                Toggle("Play a sound", isOn: $settings.alertSoundEnabled)
                    .disabled(!settings.notificationAlertsEnabled)
                if settings.notificationAlertsEnabled {
                    AlertRulesEditor()
                }
            } header: {
                Text("Notification Alerts")
            } footer: {
                Text("Separate keywords with commas. “Any word” fires on one match; “All words” needs every keyword in the same notification. Phrases like “call me” work too.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable lyrics", isOn: $settings.lyricsEnabled)
                Toggle("Show current line under the closed notch", isOn: $settings.lyricsUnderNotch)
                    .disabled(!settings.lyricsEnabled)
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Synced lyrics come from LRCLIB (lrclib.net), a free and open lyrics database. Tap the quote button in the player to show them.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Accessibility") {
                    if hud.isAccessibilityTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access", action: hud.requestAccessibilityAccess)
                    }
                }
                LabeledContent("Calendar") {
                    if calendar.hasAccess {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access", action: calendar.requestAccess)
                    }
                }
                LabeledContent("Spotify & Music control") {
                    Button("Open Automation Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Accessibility powers the volume & brightness keys and reading notification banners.")
                    .foregroundStyle(.secondary)
            }

            Section {
                @Bindable var updates = updates
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                LabeledContent("Updates") {
                    Button("Check Now", action: updates.checkForUpdates)
                }
            } header: {
                Text("Updates")
            } footer: {
                if let lastChecked = updates.lastChecked {
                    Text("Last checked \(lastChecked.formatted(.relative(presentation: .named))).")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Share anonymous usage data", isOn: $settings.shareUsageData)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Counts launches and which tabs you use, so I know what to improve. Nothing personal is ever sent.")
                    .foregroundStyle(.secondary)
            }

            AboutSection()

            Section {
                Button("Quit Notch", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .onAppear { agents.refreshHookStatus() }
        .frame(minWidth: 500, idealWidth: 520, minHeight: 520, idealHeight: 680)
    }

    private func hookRow(_ kind: AgentKind) -> some View {
        let installed = agents.hooksInstalled[kind] == true
        return LabeledContent("\(kind.displayName) hooks") {
            HStack {
                if installed {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button(installed ? "Remove" : "Install") {
                    do {
                        switch (kind, installed) {
                        case (.claude, false): try AgentHookInstaller.installClaude()
                        case (.claude, true): try AgentHookInstaller.uninstallClaude()
                        case (.codex, false): try AgentHookInstaller.installCodex()
                        case (.codex, true): try AgentHookInstaller.uninstallCodex()
                        }
                        hookError = nil
                    } catch {
                        hookError = error.localizedDescription
                    }
                    agents.refreshHookStatus()
                }
            }
        }
    }
}
