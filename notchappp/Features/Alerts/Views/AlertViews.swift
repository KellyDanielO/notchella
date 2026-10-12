import SwiftUI

/// The bell shown beside the camera housing while an alert is up.
struct AlertBellIcon: View {
    @Environment(AlertManager.self) private var alerts

    var body: some View {
        Image(systemName: "bell.badge.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.orange, .white)
            .font(.system(size: 13, weight: .semibold))
            .symbolEffect(.wiggle, options: .repeat(2), value: alerts.currentAlert?.id)
    }
}

/// The keyword that triggered the alert, as a small orange chip.
struct AlertKeywordChip: View {
    @Environment(AlertManager.self) private var alerts

    var body: some View {
        if let term = alerts.currentAlert?.matchedTerms.first {
            Text(term)
                .font(.system(size: 10.5, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(.black)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(Capsule().fill(.orange))
        }
    }
}

/// Title and body of the matched notification, with the keywords highlighted.
struct AlertBannerContent: View {
    @Environment(AlertManager.self) private var alerts

    var body: some View {
        if let alert = alerts.currentAlert {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(highlighted(alert.title, terms: alert.matchedTerms))
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    if let appName = alert.appName {
                        Text(appName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                if !alert.body.isEmpty {
                    Text(highlighted(alert.body, terms: alert.matchedTerms))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { alerts.dismiss() }
            .id(alert.id)
        }
    }

    private func highlighted(_ text: String, terms: [String]) -> AttributedString {
        var result = AttributedString(text)
        for term in terms {
            var searchRange = result.startIndex..<result.endIndex
            while let range = result[searchRange].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                result[range].foregroundColor = .orange
                result[range].font = .system(size: 12.5, weight: .heavy)
                searchRange = range.upperBound..<result.endIndex
            }
        }
        return result
    }
}

/// Settings editor for keyword rules.
struct AlertRulesEditor: View {
    @Environment(AlertManager.self) private var alerts

    var body: some View {
        ForEach(alerts.rules) { rule in
            AlertRuleRow(rule: rule)
        }
        HStack {
            Button("Add Rule", systemImage: "plus", action: alerts.addRule)
            Spacer()
            Button("Preview Alert", action: alerts.preview)
        }
    }
}

private struct AlertRuleRow: View {
    @Environment(AlertManager.self) private var alerts
    @State private var rule: AlertRule

    init(rule: AlertRule) {
        _rule = State(initialValue: rule)
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $rule.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            TextField("urgent, call me, deploy failed", text: $rule.keywords)
                .textFieldStyle(.roundedBorder)
            Picker("", selection: $rule.mode) {
                ForEach(AlertRule.Mode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button(role: .destructive) {
                alerts.remove(rule)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: rule) { _, updated in alerts.update(updated) }
    }
}
