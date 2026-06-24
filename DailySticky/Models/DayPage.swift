import Foundation

struct DayPage: Codable, Identifiable, Equatable {
    var id: String { dateKey }

    var dateKey: String
    var noteText: String
    var createdAt: Date
    var updatedAt: Date

    static func empty(dateKey: String, now: Date = Date()) -> DayPage {
        DayPage(
            dateKey: dateKey,
            noteText: "",
            createdAt: now,
            updatedAt: now
        )
    }
}
