import Foundation

final class DateKeyService {
    private let calendar: Calendar
    private var locale: Locale
    private let dateKeyFormatter: DateFormatter
    private let displayDateFormatter: DateFormatter
    private let compactDisplayDateFormatter: DateFormatter
    private let compactNavigationDateFormatter: DateFormatter
    private let shortDisplayDateFormatter: DateFormatter
    private let accessibleShortDisplayDateFormatter: DateFormatter

    init(
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        self.locale = Self.normalizedLocale(locale)

        let keyFormatter = DateFormatter()
        keyFormatter.calendar = calendar
        keyFormatter.locale = Locale(identifier: "en_US_POSIX")
        keyFormatter.timeZone = calendar.timeZone
        keyFormatter.dateFormat = "yyyy-MM-dd"
        self.dateKeyFormatter = keyFormatter

        let displayFormatter = DateFormatter()
        displayFormatter.calendar = calendar
        displayFormatter.locale = self.locale
        displayFormatter.timeZone = calendar.timeZone
        displayFormatter.setLocalizedDateFormatFromTemplate("yMMMMEEEEd")
        self.displayDateFormatter = displayFormatter

        let compactDisplayFormatter = DateFormatter()
        compactDisplayFormatter.calendar = calendar
        compactDisplayFormatter.locale = self.locale
        compactDisplayFormatter.timeZone = calendar.timeZone
        compactDisplayFormatter.setLocalizedDateFormatFromTemplate("yMMMd")
        self.compactDisplayDateFormatter = compactDisplayFormatter

        let compactNavigationFormatter = DateFormatter()
        compactNavigationFormatter.calendar = calendar
        compactNavigationFormatter.locale = self.locale
        compactNavigationFormatter.timeZone = calendar.timeZone
        compactNavigationFormatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        self.compactNavigationDateFormatter = compactNavigationFormatter

        let shortDisplayFormatter = DateFormatter()
        shortDisplayFormatter.calendar = calendar
        shortDisplayFormatter.locale = self.locale
        shortDisplayFormatter.timeZone = calendar.timeZone
        shortDisplayFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        self.shortDisplayDateFormatter = shortDisplayFormatter

        let accessibleShortDisplayFormatter = DateFormatter()
        accessibleShortDisplayFormatter.calendar = calendar
        accessibleShortDisplayFormatter.locale = self.locale
        accessibleShortDisplayFormatter.timeZone = calendar.timeZone
        accessibleShortDisplayFormatter.setLocalizedDateFormatFromTemplate("MMMMd")
        self.accessibleShortDisplayDateFormatter = accessibleShortDisplayFormatter
    }

    func updateLocale(_ locale: Locale) {
        let normalizedLocale = Self.normalizedLocale(locale)
        guard normalizedLocale.identifier != self.locale.identifier else {
            return
        }

        self.locale = normalizedLocale
        displayDateFormatter.locale = normalizedLocale
        displayDateFormatter.setLocalizedDateFormatFromTemplate("yMMMMEEEEd")
        compactDisplayDateFormatter.locale = normalizedLocale
        compactDisplayDateFormatter.setLocalizedDateFormatFromTemplate("yMMMd")
        compactNavigationDateFormatter.locale = normalizedLocale
        compactNavigationDateFormatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        shortDisplayDateFormatter.locale = normalizedLocale
        shortDisplayDateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        accessibleShortDisplayDateFormatter.locale = normalizedLocale
        accessibleShortDisplayDateFormatter.setLocalizedDateFormatFromTemplate("MMMMd")
    }

    private static func normalizedLocale(_ locale: Locale) -> Locale {
        guard locale.language.languageCode?.identifier == "en" else {
            return locale
        }
        return Locale(identifier: "en_US")
    }

    func todayDateKey() -> String {
        dateKey(for: Date())
    }

    func dateKey(for date: Date) -> String {
        dateKeyFormatter.string(from: date)
    }

    func date(from dateKey: String) -> Date? {
        dateKeyFormatter.date(from: dateKey)
    }

    func isValidDateKey(_ dateKey: String) -> Bool {
        guard let date = date(from: dateKey) else {
            return false
        }

        return self.dateKey(for: date) == dateKey
    }

    func dateKey(byAddingDays days: Int, to dateKey: String) -> String? {
        guard
            let date = date(from: dateKey),
            let movedDate = calendar.date(byAdding: .day, value: days, to: date)
        else {
            return nil
        }

        return self.dateKey(for: movedDate)
    }

    func displayTitle(for dateKey: String) -> String {
        guard let date = date(from: dateKey) else {
            return dateKey
        }

        return displayDateFormatter.string(from: date)
    }

    func compactDisplayTitle(for dateKey: String) -> String {
        guard let date = date(from: dateKey) else {
            return dateKey
        }

        return compactDisplayDateFormatter.string(from: date)
    }

    func compactNavigationTitle(for dateKey: String) -> String {
        guard let date = date(from: dateKey) else {
            return dateKey
        }

        return compactNavigationDateFormatter.string(from: date)
    }

    func shortDisplayTitle(for dateKey: String) -> String {
        guard let date = date(from: dateKey) else {
            return dateKey
        }

        return shortDisplayDateFormatter.string(from: date)
    }

    func accessibleShortDisplayTitle(for dateKey: String) -> String {
        guard let date = date(from: dateKey) else {
            return dateKey
        }

        return accessibleShortDisplayDateFormatter.string(from: date)
    }
}
