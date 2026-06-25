import Foundation

enum AppThemeKind: String, Codable, CaseIterable, Identifiable {
    case yellow
    case light
    case dark

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .yellow:
            return "Yellow"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var lastOpenedDateKey: String
    var isPinned: Bool
    var windowFrame: StoredWindowFrame?
    var theme: AppThemeKind
    var noteOpacity: Double

    init(
        lastOpenedDateKey: String,
        isPinned: Bool,
        windowFrame: StoredWindowFrame?,
        theme: AppThemeKind = .yellow,
        noteOpacity: Double = 1.0
    ) {
        self.lastOpenedDateKey = lastOpenedDateKey
        self.isPinned = isPinned
        self.windowFrame = windowFrame
        self.theme = theme
        self.noteOpacity = Self.clampedOpacity(noteOpacity)
    }

    private enum CodingKeys: String, CodingKey {
        case lastOpenedDateKey
        case isPinned
        case windowFrame
        case theme
        case noteOpacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastOpenedDateKey = try container.decode(String.self, forKey: .lastOpenedDateKey)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        windowFrame = try container.decodeIfPresent(StoredWindowFrame.self, forKey: .windowFrame)
        theme = try container.decodeIfPresent(AppThemeKind.self, forKey: .theme) ?? .yellow
        noteOpacity = Self.clampedOpacity(
            try container.decodeIfPresent(Double.self, forKey: .noteOpacity) ?? 1.0
        )
    }

    static func clampedOpacity(_ opacity: Double) -> Double {
        min(1.0, max(0.0, opacity))
    }
}
