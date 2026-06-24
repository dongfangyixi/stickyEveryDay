import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    private enum SaveMode {
        case debounced
        case immediate
    }

    @Published private(set) var data: AppData
    @Published private(set) var currentDateKey: String
    @Published private(set) var isPinned: Bool
    @Published var lastErrorMessage: String?

    private let dataStore: AppDataStore
    private let dateKeyService: DateKeyService
    private let dayPageController: DayPageController
    private let autoSaveService: AutoSaveService

    var currentPage: DayPage {
        data.pages[currentDateKey] ?? DayPage.empty(dateKey: currentDateKey)
    }

    var currentDateTitle: String {
        dateKeyService.displayTitle(for: currentDateKey)
    }

    var isShowingToday: Bool {
        currentDateKey == dateKeyService.todayDateKey()
    }

    var dataFilePath: String {
        dataStore.dataFileURL.path
    }

    init(
        dataStore: AppDataStore,
        dateKeyService: DateKeyService,
        dayPageController: DayPageController? = nil,
        autoSaveService: AutoSaveService? = nil
    ) {
        let todayDateKey = dateKeyService.todayDateKey()
        let pageController = dayPageController ?? DayPageController(dateKeyService: dateKeyService)

        var loadWarning: String?
        var loadedData: AppData

        do {
            loadedData = try dataStore.load(defaultDateKey: todayDateKey)
        } catch {
            loadedData = AppData.empty(todayDateKey: todayDateKey)
            loadWarning = error.localizedDescription
        }

        var dateKeyToOpen = loadedData.settings.lastOpenedDateKey
        var shouldSaveAfterInit = false

        if !dateKeyService.isValidDateKey(dateKeyToOpen) {
            dateKeyToOpen = todayDateKey
            loadedData.settings.lastOpenedDateKey = todayDateKey
            shouldSaveAfterInit = true
        }

        if pageController.ensurePage(dateKey: dateKeyToOpen, in: &loadedData) {
            shouldSaveAfterInit = true
        }

        self.data = loadedData
        self.currentDateKey = dateKeyToOpen
        self.isPinned = loadedData.settings.isPinned
        self.lastErrorMessage = loadWarning
        self.dataStore = dataStore
        self.dateKeyService = dateKeyService
        self.dayPageController = pageController
        self.autoSaveService = autoSaveService ?? AutoSaveService()

        if shouldSaveAfterInit {
            saveImmediately()
        }
    }

    func goToPreviousDay() {
        guard let previousDateKey = dayPageController.previousDateKey(from: currentDateKey) else {
            return
        }

        openDate(previousDateKey)
    }

    func goToNextDay() {
        guard let nextDateKey = dayPageController.nextDateKey(from: currentDateKey) else {
            return
        }

        openDate(nextDateKey)
    }

    func jumpToToday() {
        openDate(dateKeyService.todayDateKey())
    }

    func openDate(_ dateKey: String) {
        guard dateKeyService.isValidDateKey(dateKey) else {
            return
        }

        currentDateKey = dateKey

        mutateData(saveMode: .immediate) { data in
            _ = dayPageController.ensurePage(dateKey: dateKey, in: &data)
            data.settings.lastOpenedDateKey = dateKey
        }
    }

    func updateNoteText(_ noteText: String) {
        mutateData(saveMode: .debounced) { data in
            dayPageController.updateNoteText(noteText, dateKey: currentDateKey, in: &data)
        }
    }

    func togglePinned() {
        mutateData(saveMode: .immediate) { data in
            data.settings.isPinned.toggle()
        }
    }

    func updateWindowFrame(_ frame: StoredWindowFrame) {
        data.settings.windowFrame = frame
        saveDebounced()
    }

    func saveImmediately() {
        autoSaveService.cancel()
        saveNow()
    }

    private func mutateData(saveMode: SaveMode, _ mutation: (inout AppData) -> Void) {
        objectWillChange.send()
        mutation(&data)
        isPinned = data.settings.isPinned

        switch saveMode {
        case .debounced:
            saveDebounced()
        case .immediate:
            saveImmediately()
        }
    }

    private func saveDebounced() {
        autoSaveService.schedule { [weak self] in
            self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            try dataStore.save(data)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
