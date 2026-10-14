import SwiftUI

/// The closed notch. Shows small "wings" beside the camera housing when a live activity runs,
/// and drops down a banner when a notification alert fires.
struct ClosedNotchView: View {
    let namespace: Namespace.ID

    @Environment(NotchViewModel.self) private var notch
    @Environment(MusicManager.self) private var music
    @Environment(BatteryManager.self) private var battery
    @Environment(DownloadMonitor.self) private var downloads
    @Environment(IdleManager.self) private var idle
    @Environment(AgentMonitor.self) private var agents

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leadingWing
                    .frame(width: notch.wingWidth, alignment: .leading)
                Color.clear
                    .frame(width: notch.notchSize.width)
                trailingWing
                    .frame(width: notch.wingWidth, alignment: .trailing)
            }
            .frame(height: notch.notchSize.height)
            .animation(.notchActivity, value: notch.activity)

            if notch.activity == .affirmation {
                AmbientAffirmationView()
                    .padding(.horizontal, 24)
                    .frame(height: NotchViewModel.affirmationHeight, alignment: .top)
                    .transition(.blurFade)
            } else if notch.activity == .alert {
                AlertBannerContent()
                    .padding(.horizontal, 20)
                    .frame(height: NotchViewModel.alertHeight, alignment: .top)
                    .transition(.blurFade)
            } else if notch.showsLyricLine {
                ClosedLyricLineView()
                    .padding(.horizontal, 10)
                    .frame(height: NotchViewModel.lyricLineHeight, alignment: .top)
                    .transition(.blurFade)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
    }

    @ViewBuilder
    private var leadingWing: some View {
        switch notch.activity {
        case .music:
            ArtworkView(image: music.artwork, size: notch.notchSize.height - 10, cornerRadius: 6)
                .matchedGeometryEffect(id: "artwork", in: namespace)
                .padding(.leading, 6)
                .transition(.blurFade.combined(with: .scale(scale: 0.5)))
        case .charging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.leading, 10)
                .transition(.blurFade.combined(with: .scale(scale: 0.5)))
        case .hud:
            HUDIcon(size: 13)
                .padding(.leading, 6)
                .transition(.blurFade.combined(with: .scale(scale: 0.5)))
        case .alert:
            AlertBellIcon()
                .padding(.leading, 14)
                .transition(.blurFade.combined(with: .scale(scale: 0.5)))
        case .agent:
            AgentClosedLeading()
                .padding(.leading, 12)
                .transition(.blurFade.combined(with: .scale(scale: 0.5)))
        case .build:
            XcodeClosedLeading()
                .padding(.leading, 12)
                .transition(.blurFade.combined(with: .scale(scale: 0.5)))
        case .headphones:
            HeadphonesClosedLeading()
                .padding(.leading, 10)
                .transition(.blurFade.combined(with: .scale(scale: 0.5)))
        case .download:
            DownloadClosedLeading()
                .padding(.leading, 12)
                .transition(.blurFade.combined(with: .scale(scale: 0.5)))
        case .breakNudge:
            BreakNudgeLeading()
                .padding(.leading, 12)
                .transition(.blurFade.combined(with: .scale(scale: 0.5)))
        case .idle:
            NotchEye(side: .left)
                .frame(maxWidth: .infinity)
                .transition(.blurFade.combined(with: .scale(scale: 0.3)))
        case .affirmation:
            EmptyView()
        case .charged:
            Image(systemName: "battery.100percent.bolt")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.leading, 10)
                .transition(.blurFade.combined(with: .scale(scale: 0.5)))
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingWing: some View {
        switch notch.activity {
        case .music:
            AudioVisualizer(isPlaying: music.isPlaying, color: music.accentColor)
                .frame(width: notch.wingWidth - 12)
                .padding(.trailing, 6)
                .transition(.blurFade)
        case .charging:
            Text("\(battery.level)%")
                .font(.system(size: 12, weight: .heavy).monospacedDigit())
                .foregroundStyle(.green)
                .padding(.trailing, 10)
                .transition(.blurFade)
        case .hud:
            HUDSegmentMeter()
                .padding(.trailing, 6)
                .transition(.blurFade)
        case .alert:
            AlertKeywordChip()
                .padding(.trailing, 10)
                .transition(.blurFade)
        case .agent:
            AgentClosedTrailing()
                .padding(.trailing, 10)
                .transition(.blurFade)
        case .build:
            XcodeClosedTrailing()
                .padding(.trailing, 10)
                .transition(.blurFade)
        case .headphones:
            HeadphonesClosedTrailing()
                .padding(.trailing, 10)
                .transition(.blurFade)
        case .download:
            DownloadClosedTrailing()
                .padding(.trailing, 10)
                .transition(.blurFade)
        case .breakNudge:
            BreakNudgeTrailing()
                .padding(.trailing, 10)
                .transition(.blurFade)
        case .idle:
            NotchEye(side: .right)
                .frame(maxWidth: .infinity)
                .transition(.blurFade.combined(with: .scale(scale: 0.3)))
        case .affirmation:
            EmptyView()
        case .charged:
            Text(battery.level >= 100 ? "Charged" : "\(battery.level)% ✓")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.green)
                .padding(.trailing, 10)
                .transition(.blurFade)
        case .none:
            EmptyView()
        }
    }

    /// Taps act on what's showing: dismiss nudges, reveal a finished download, or open the notch.
    private func handleTap() {
        switch notch.activity {
        case .alert:
            break
        case .affirmation:
            idle.dismissAmbientAffirmation()
            notch.open(tab: .reflect)
        case .breakNudge:
            agents.dismissBreakNudge()
        case .download where downloads.justFinished != nil && downloads.fraction == nil:
            downloads.revealFinished()
        default:
            notch.open()
        }
    }
}
