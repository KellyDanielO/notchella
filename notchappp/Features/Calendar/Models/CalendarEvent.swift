import SwiftUI

nonisolated struct CalendarEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}
