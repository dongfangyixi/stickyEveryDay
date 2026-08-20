import Foundation

enum AppThemeKind: String, Codable, CaseIterable, Identifiable {
    case yellow
    case light
    case dark

    var id: String {
        rawValue
    }

    var localizationKey: String {
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
    var language: AppLanguage
    var noteOpacity: Double
    var hasSeenWelcome: Bool
    var storageMode: StorageMode
    var hasChosenStorageMode: Bool

    init(
        lastOpenedDateKey: String,
        isPinned: Bool,
        windowFrame: StoredWindowFrame?,
        theme: AppThemeKind = .yellow,
        language: AppLanguage = .english,
        noteOpacity: Double = 1.0,
        hasSeenWelcome: Bool = false,
        storageMode: StorageMode = .localOnly,
        hasChosenStorageMode: Bool = false
    ) {
        self.lastOpenedDateKey = lastOpenedDateKey
        self.isPinned = isPinned
        self.windowFrame = windowFrame
        self.theme = theme
        self.language = language
        self.noteOpacity = Self.clampedOpacity(noteOpacity)
        self.hasSeenWelcome = hasSeenWelcome
        self.storageMode = storageMode
        self.hasChosenStorageMode = hasChosenStorageMode
    }

    private enum CodingKeys: String, CodingKey {
        case lastOpenedDateKey
        case isPinned
        case windowFrame
        case theme
        case language
        case noteOpacity
        case hasSeenWelcome
        case storageMode
        case hasChosenStorageMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastOpenedDateKey = try container.decode(String.self, forKey: .lastOpenedDateKey)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        windowFrame = try container.decodeIfPresent(StoredWindowFrame.self, forKey: .windowFrame)
        theme = try container.decodeIfPresent(AppThemeKind.self, forKey: .theme) ?? .yellow
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
        noteOpacity = Self.clampedOpacity(
            try container.decodeIfPresent(Double.self, forKey: .noteOpacity) ?? 1.0
        )
        hasSeenWelcome = try container.decodeIfPresent(Bool.self, forKey: .hasSeenWelcome) ?? false
        storageMode = try container.decodeIfPresent(StorageMode.self, forKey: .storageMode) ?? .localOnly
        hasChosenStorageMode = try container.decodeIfPresent(Bool.self, forKey: .hasChosenStorageMode) ?? false
    }

    static func clampedOpacity(_ opacity: Double) -> Double {
        min(1.0, max(0.0, opacity))
    }
}
