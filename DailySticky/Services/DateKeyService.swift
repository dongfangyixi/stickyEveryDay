import Foundation

struct DateTickerFaceContent: Equatable {
    let weekday: String
    let day: String
    let month: String
    let accessibilityTitle: String
}

final class DateKeyService {
    private let calendar: Calendar
    private var locale: Locale
    private let dateKeyFormatter: DateFormatter
    private let displayDateFormatter: DateFormatter
    private let compactDisplayDateFormatter: DateFormatter
    private let compactNavigationDateFormatter: DateFormatter
    private let shortDisplayDateFormatter: DateFormatter
    private let accessibleShortDisplayDateFormatter: DateFormatter
    private let tickerWeekdayFormatter: DateFormatter
    private let tickerDayFormatter: DateFormatter
    private let tickerMonthFormatter: DateFormatter

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

        let tickerWeekdayFormatter = DateFormatter()
        tickerWeekdayFormatter.calendar = calendar
        tickerWeekdayFormatter.locale = self.locale
        tickerWeekdayFormatter.timeZone = calendar.timeZone
        tickerWeekdayFormatter.setLocalizedDateFormatFromTemplate("EEE")
        self.tickerWeekdayFormatter = tickerWeekdayFormatter

        let tickerDayFormatter = DateFormatter()
        tickerDayFormatter.calendar = calendar
        tickerDayFormatter.locale = self.locale
        tickerDayFormatter.timeZone = calendar.timeZone
        tickerDayFormatter.setLocalizedDateFormatFromTemplate("d")
        self.tickerDayFormatter = tickerDayFormatter

        let tickerMonthFormatter = DateFormatter()
        tickerMonthFormatter.calendar = calendar
        tickerMonthFormatter.locale = self.locale
        tickerMonthFormatter.timeZone = calendar.timeZone
        tickerMonthFormatter.setLocalizedDateFormatFromTemplate("MMM")
        self.tickerMonthFormatter = tickerMonthFormatter
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
        tickerWeekdayFormatter.locale = normalizedLocale
        tickerWeekdayFormatter.setLocalizedDateFormatFromTemplate("EEE")
        tickerDayFormatter.locale = normalizedLocale
        tickerDayFormatter.setLocalizedDateFormatFromTemplate("d")
        tickerMonthFormatter.locale = normalizedLocale
        tickerMonthFormatter.setLocalizedDateFormatFromTemplate("MMM")
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

    func dayOffset(from startDateKey: String, to endDateKey: String) -> Int? {
        guard
            let startDate = date(from: startDateKey),
            let endDate = date(from: endDateKey)
        else {
            return nil
        }

        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: startDate),
            to: calendar.startOfDay(for: endDate)
        ).day
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

    func tickerFaceContent(for dateKey: String) -> DateTickerFaceContent? {
        guard let date = date(from: dateKey) else {
            return nil
        }

        return DateTickerFaceContent(
            weekday: tickerWeekdayFormatter.string(from: date).uppercased(with: locale),
            day: tickerDayFormatter.string(from: date),
            month: tickerMonthFormatter.string(from: date).uppercased(with: locale),
            accessibilityTitle: displayDateFormatter.string(from: date)
        )
    }
}
