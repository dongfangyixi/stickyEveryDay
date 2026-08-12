import Foundation

final class DateKeyService {
    private let calendar: Calendar
    private let locale: Locale
    private let dateKeyFormatter: DateFormatter
    private let displayDateFormatter: DateFormatter
    private let compactDisplayDateFormatter: DateFormatter
    private let shortDisplayDateFormatter: DateFormatter

    init(
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        self.locale = locale

        let keyFormatter = DateFormatter()
        keyFormatter.calendar = calendar
        keyFormatter.locale = Locale(identifier: "en_US_POSIX")
        keyFormatter.timeZone = calendar.timeZone
        keyFormatter.dateFormat = "yyyy-MM-dd"
        self.dateKeyFormatter = keyFormatter

        let displayFormatter = DateFormatter()
        displayFormatter.calendar = calendar
        displayFormatter.locale = locale
        displayFormatter.timeZone = calendar.timeZone
        displayFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        self.displayDateFormatter = displayFormatter

        let compactDisplayFormatter = DateFormatter()
        compactDisplayFormatter.calendar = calendar
        compactDisplayFormatter.locale = locale
        compactDisplayFormatter.timeZone = calendar.timeZone
        compactDisplayFormatter.dateFormat = "MMM d, yyyy"
        self.compactDisplayDateFormatter = compactDisplayFormatter

        let shortDisplayFormatter = DateFormatter()
        shortDisplayFormatter.calendar = calendar
        shortDisplayFormatter.locale = locale
        shortDisplayFormatter.timeZone = calendar.timeZone
        shortDisplayFormatter.dateFormat = "MMM d"
        self.shortDisplayDateFormatter = shortDisplayFormatter
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

        var formatStyle = Date.FormatStyle()
        formatStyle.calendar = calendar
        formatStyle.locale = locale
        formatStyle.timeZone = calendar.timeZone
        return date.formatted(
            formatStyle
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
        )
    }

    func shortDisplayTitle(for dateKey: String) -> String {
        guard let date = date(from: dateKey) else {
            return dateKey
        }

        var formatStyle = Date.FormatStyle()
        formatStyle.calendar = calendar
        formatStyle.locale = locale
        formatStyle.timeZone = calendar.timeZone
        return date.formatted(formatStyle.month(.abbreviated).day())
    }

    func accessibleShortDisplayTitle(for dateKey: String) -> String {
        guard let date = date(from: dateKey) else {
            return dateKey
        }

        var formatStyle = Date.FormatStyle()
        formatStyle.calendar = calendar
        formatStyle.locale = locale
        formatStyle.timeZone = calendar.timeZone
        return date.formatted(formatStyle.month(.wide).day())
    }
}
