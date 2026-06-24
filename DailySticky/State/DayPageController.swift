import Foundation

final class DayPageController {
    private let dateKeyService: DateKeyService

    init(dateKeyService: DateKeyService) {
        self.dateKeyService = dateKeyService
    }

    func ensurePage(dateKey: String, in data: inout AppData, now: Date = Date()) -> Bool {
        guard data.pages[dateKey] == nil else {
            return false
        }

        data.pages[dateKey] = DayPage.empty(dateKey: dateKey, now: now)
        return true
    }

    func previousDateKey(from dateKey: String) -> String? {
        dateKeyService.dateKey(byAddingDays: -1, to: dateKey)
    }

    func nextDateKey(from dateKey: String) -> String? {
        dateKeyService.dateKey(byAddingDays: 1, to: dateKey)
    }

    func updateNoteText(_ noteText: String, dateKey: String, in data: inout AppData, now: Date = Date()) {
        _ = ensurePage(dateKey: dateKey, in: &data, now: now)

        guard var page = data.pages[dateKey] else {
            return
        }

        page.noteText = noteText
        page.updatedAt = now
        data.pages[dateKey] = page
    }
}

