import Foundation

struct AppData: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var pages: [String: DayPage]
    var settings: AppSettings

    static func empty(todayDateKey: String, now: Date = Date()) -> AppData {
        AppData(
            schemaVersion: currentSchemaVersion,
            pages: [
                todayDateKey: DayPage.empty(dateKey: todayDateKey, now: now)
            ],
            settings: AppSettings(
                lastOpenedDateKey: todayDateKey,
                isPinned: true,
                windowFrame: nil
            )
        )
    }
}
