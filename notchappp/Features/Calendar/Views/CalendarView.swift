import SwiftUI

/// A one-day agenda card: big date on top, the day's events below.
struct CalendarView: View {
    @Environment(CalendarManager.self) private var calendar
    @State private var direction: Edge = .trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Group {
                if !calendar.hasAccess {
                    accessPrompt
                } else if calendar.events.isEmpty {
                    emptyState
                } else {
                    eventList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(calendar.selectedDate)
            .transition(.push(from: direction).combined(with: .opacity))
        }
    }

    private var header: some View {
        let date = calendar.selectedDate
        let isToday = calendar.isToday(date)

        return HStack(alignment: .center, spacing: 8) {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 30, weight: .heavy).monospacedDigit())
                .contentTransition(.numericText(value: date.timeIntervalSince1970))
            VStack(alignment: .leading, spacing: 0) {
                Text(isToday ? "Today" : date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isToday ? Color.red : .white)
                Text(date.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                NotchIconButton(symbol: "chevron.left", size: 9, tint: .secondary) { shift(by: -1) }
                if !isToday {
                    NotchIconButton(symbol: "smallcircle.filled.circle", size: 9, tint: .secondary) {
                        direction = calendar.selectedDate > .now ? .leading : .trailing
                        withAnimation(.smooth(duration: 0.35)) { calendar.goToToday() }
                    }
                    .help("Today")
                    .transition(.scale.combined(with: .opacity))
                }
                NotchIconButton(symbol: "chevron.right", size: 9, tint: .secondary) { shift(by: 1) }
            }
        }
    }

    private func shift(by days: Int) {
        direction = days > 0 ? .trailing : .leading
        withAnimation(.smooth(duration: 0.35)) { calendar.shiftDay(by: days) }
    }

    private var eventList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(calendar.events) { event in
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(event.color)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(timeRange(for: event))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(event.color.opacity(0.12))
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Nothing scheduled")
                    .font(.system(size: 12, weight: .bold))
                Text("The day is all yours.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var accessPrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bring your day into the notch.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Button("Connect Calendar", action: calendar.requestAccess)
                .buttonStyle(PressableButtonStyle())
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.14)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func timeRange(for event: CalendarEvent) -> String {
        if event.isAllDay { return "All day" }
        let style = Date.FormatStyle.dateTime.hour().minute()
        return "\(event.start.formatted(style)) – \(event.end.formatted(style))"
    }
}
