import EventKit
import SwiftUI

/// Reads the system calendar's events for the selected day.
@Observable
final class CalendarManager {
    private(set) var authorization = EKEventStore.authorizationStatus(for: .event)
    private(set) var selectedDate: Date
    private(set) var events: [CalendarEvent] = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let calendar = Calendar.current
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var hasAccess: Bool { authorization == .fullAccess }

    init() {
        let today = Calendar.current.startOfDay(for: .now)
        selectedDate = today

        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadEvents() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.goToToday() }
        })
        reloadEvents()
    }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            authorization = EKEventStore.authorizationStatus(for: .event)
            reloadEvents()
        }
    }

    func select(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        reloadEvents()
    }

    func shiftDay(by days: Int) {
        guard let date = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        select(date)
    }

    func goToToday() {
        select(.now)
    }

    func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }

    private func reloadEvents() {
        guard hasAccess, let end = calendar.date(byAdding: .day, value: 1, to: selectedDate) else {
            events = []
            return
        }
        let predicate = store.predicateForEvents(withStart: selectedDate, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { event in
                CalendarEvent(
                    id: event.calendarItemIdentifier + "\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: Color(cgColor: event.calendar.cgColor)
                )
            }
    }
}
