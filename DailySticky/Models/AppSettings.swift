import Foundation

struct AppSettings: Codable, Equatable {
    var lastOpenedDateKey: String
    var isPinned: Bool
    var windowFrame: StoredWindowFrame?
}

