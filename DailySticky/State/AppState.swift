import Combine
import Foundation

enum HeaderReturnState: Equatable {
    case none
    case today
    case searchOrigin(dateKey: String)
}

@MainActor
final class AppState: ObservableObject {
    private enum SaveMode {
        case debounced
        case immediate
    }

    @Published private(set) var data: AppData
    @Published private(set) var currentDateKey: String
    @Published private(set) var isPinned: Bool
    @Published private(set) var theme: AppThemeKind
    @Published private(set) var language: AppLanguage
    @Published private(set) var noteOpacity: Double
    @Published private(set) var hasSeenWelcome: Bool
    @Published private(set) var storageMode: StorageMode
    @Published private(set) var hasChosenStorageMode: Bool
    @Published private(set) var cloudSyncStatus: CloudSyncStatus
    @Published private(set) var isNoteSearchPresented = false
    @Published private(set) var searchReturnDateKey: String?
    @Published private(set) var noteRevealRequest: NoteRevealRequest?
    @Published var lastErrorMessage: String?

    private let dataStore: AppDataStore
    private let dateKeyService: DateKeyService
    private let dayPageController: DayPageController
    private let autoSaveService: AutoSaveService
    private let cloudRefreshInterval: TimeInterval
    private var cloudSyncCoordinator: CloudSyncCoordinator?
    private var cloudRefreshTask: Task<Void, Never>?

    var currentPage: DayPage {
        data.pages[currentDateKey] ?? DayPage.empty(dateKey: currentDateKey)
    }

    var currentDateTitle: String {
        dateKeyService.displayTitle(for: currentDateKey)
    }

    var currentCompactDateTitle: String {
        dateKeyService.compactDisplayTitle(for: currentDateKey)
    }

    var currentShortDateTitle: String {
        dateKeyService.compactNavigationTitle(for: currentDateKey)
    }

    var isShowingToday: Bool {
        currentDateKey == dateKeyService.todayDateKey()
    }

    var dataFilePath: String {
        dataStore.dataFileURL.path
    }

    var headerReturnState: HeaderReturnState {
        if let searchReturnDateKey, searchReturnDateKey != currentDateKey {
            return .searchOrigin(dateKey: searchReturnDateKey)
        }
        return isShowingToday ? .none : .today
    }

    var themePalette: AppTheme.Palette {
        AppTheme.palette(for: theme)
    }

    func displayTitle(for dateKey: String) -> String {
        dateKeyService.displayTitle(for: dateKey)
    }

    func shortDisplayTitle(for dateKey: String) -> String {
        dateKeyService.shortDisplayTitle(for: dateKey)
    }

    func accessibleShortDisplayTitle(for dateKey: String) -> String {
        dateKeyService.accessibleShortDisplayTitle(for: dateKey)
    }

    init(
        dataStore: AppDataStore,
        dateKeyService: DateKeyService,
        dayPageController: DayPageController? = nil,
        autoSaveService: AutoSaveService? = nil,
        cloudSyncService: CloudSyncServicing? = nil,
        cloudSyncMetadataStore: CloudSyncMetadataStore = CloudSyncMetadataStore(),
        cloudRefreshInterval: TimeInterval = 20
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
        self.theme = loadedData.settings.theme
        self.language = loadedData.settings.language
        self.noteOpacity = loadedData.settings.noteOpacity
        self.hasSeenWelcome = loadedData.settings.hasSeenWelcome
        self.storageMode = loadedData.settings.storageMode
        self.hasChosenStorageMode = loadedData.settings.hasChosenStorageMode
        self.cloudSyncStatus = loadedData.settings.storageMode == .iCloud ? .checkingAccount : .localOnly
        self.lastErrorMessage = loadWarning
        self.dataStore = dataStore
        self.dateKeyService = dateKeyService
        self.dayPageController = pageController
        self.autoSaveService = autoSaveService ?? AutoSaveService()
        self.cloudRefreshInterval = cloudRefreshInterval
        if let cloudSyncService {
            self.cloudSyncCoordinator = CloudSyncCoordinator(
                service: cloudSyncService,
                metadataStore: cloudSyncMetadataStore
            )
        }
        dateKeyService.updateLocale(loadedData.settings.language.locale)

        cloudSyncCoordinator?.onStatusChange = { [weak self] status in
            self?.cloudSyncStatus = status
        }
        cloudSyncCoordinator?.onResult = { [weak self] result, sourceSnapshot in
            try self?.applyCloudSyncResult(result, sourceSnapshot: sourceSnapshot)
        }

        if shouldSaveAfterInit {
            saveImmediately()
        }

        if storageMode == .iCloud, hasChosenStorageMode {
            startCloudRefresh()
            syncNow()
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

    func presentNoteSearch() {
        isNoteSearchPresented = true
    }

    func dismissNoteSearch() {
        isNoteSearchPresented = false
    }

    func openSearchResult(_ dateKey: String) {
        guard dateKeyService.isValidDateKey(dateKey) else {
            return
        }

        let todayDateKey = dateKeyService.todayDateKey()
        if dateKey != currentDateKey,
           searchReturnDateKey == nil,
           currentDateKey != todayDateKey {
            searchReturnDateKey = currentDateKey
        }
        isNoteSearchPresented = false
        noteRevealRequest = nil
        openDatePreservingSearchOrigin(dateKey)
    }

    func openSearchResult(_ result: NoteSearchResult, query: String) {
        openSearchResult(result.dateKey)
        guard result.kind == .content,
              let location = result.matchLocation
        else {
            return
        }
        noteRevealRequest = NoteRevealRequest(
            dateKey: result.dateKey,
            query: query,
            location: location
        )
    }

    func returnToSearchOrigin() {
        guard let returnDateKey = searchReturnDateKey else {
            return
        }

        searchReturnDateKey = nil
        noteRevealRequest = nil
        openDatePreservingSearchOrigin(returnDateKey)
    }

    func openDate(_ dateKey: String) {
        guard dateKeyService.isValidDateKey(dateKey) else {
            return
        }

        searchReturnDateKey = nil
        noteRevealRequest = nil
        openDatePreservingSearchOrigin(dateKey)
    }

    private func openDatePreservingSearchOrigin(_ dateKey: String) {
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
        noteRevealRequest = nil
        mutateData(saveMode: .debounced) { data in
            dayPageController.updateNoteText(noteText, dateKey: currentDateKey, in: &data)
        }
    }

    func togglePinned() {
        mutateData(saveMode: .immediate) { data in
            data.settings.isPinned.toggle()
        }
    }

    func updatePinned(_ isPinned: Bool) {
        mutateData(saveMode: .immediate) { data in
            data.settings.isPinned = isPinned
        }
    }

    func updateTheme(_ theme: AppThemeKind) {
        mutateData(saveMode: .immediate) { data in
            data.settings.theme = theme
        }
    }

    func updateLanguage(_ language: AppLanguage) {
        dateKeyService.updateLocale(language.locale)
        mutateData(saveMode: .immediate) { data in
            data.settings.language = language
        }
    }

    func localized(_ key: String) -> String {
        language.localized(key)
    }

    func updateNoteOpacity(_ noteOpacity: Double) {
        mutateData(saveMode: .debounced) { data in
            data.settings.noteOpacity = AppSettings.clampedOpacity(noteOpacity)
        }
    }

    func markWelcomeSeen() {
        guard !data.settings.hasSeenWelcome else {
            return
        }

        mutateData(saveMode: .immediate) { data in
            data.settings.hasSeenWelcome = true
        }
    }

    func chooseStorageMode(_ storageMode: StorageMode) {
        let changed = data.settings.storageMode != storageMode
            || !data.settings.hasChosenStorageMode
        guard changed else {
            if storageMode == .iCloud {
                syncNow()
            }
            return
        }

        if storageMode == .localOnly {
            stopCloudRefresh()
            cloudSyncCoordinator?.disable()
        }

        mutateData(saveMode: .immediate) { data in
            data.settings.storageMode = storageMode
            data.settings.hasChosenStorageMode = true
        }

        if storageMode == .iCloud {
            startCloudRefresh()
            syncNow()
        }
    }

    func syncNow() {
        guard storageMode == .iCloud else {
            cloudSyncStatus = .localOnly
            return
        }
        guard let cloudSyncCoordinator else {
            cloudSyncStatus = .capabilityUnavailable
            return
        }
        cloudSyncCoordinator.synchronizeNow(snapshot: cloudSyncSnapshot())
    }

    func appDidBecomeActive() {
        guard storageMode == .iCloud, hasChosenStorageMode else {
            return
        }
        startCloudRefresh()
        syncNow()
    }

    func appDidResignActive() {
        stopCloudRefresh()
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
        theme = data.settings.theme
        language = data.settings.language
        noteOpacity = data.settings.noteOpacity
        hasSeenWelcome = data.settings.hasSeenWelcome
        storageMode = data.settings.storageMode
        hasChosenStorageMode = data.settings.hasChosenStorageMode

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
            if storageMode == .iCloud {
                cloudSyncCoordinator?.schedule(snapshot: cloudSyncSnapshot())
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func cloudSyncSnapshot() -> CloudSyncSnapshot {
        CloudSyncSnapshot(
            pages: data.pages,
            attachments: AttachmentStore.syncSnapshot()
        )
    }

    private func startCloudRefresh() {
        stopCloudRefresh()
        guard cloudRefreshInterval > 0 else {
            return
        }

        let delay = UInt64(cloudRefreshInterval * 1_000_000_000)
        cloudRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard let self,
                      self.storageMode == .iCloud,
                      self.hasChosenStorageMode
                else {
                    return
                }
                self.syncNow()
            }
        }
    }

    private func stopCloudRefresh() {
        cloudRefreshTask?.cancel()
        cloudRefreshTask = nil
    }

    private func applyCloudSyncResult(
        _ result: CloudSyncResult,
        sourceSnapshot: CloudSyncSnapshot
    ) throws {
        let reconciliation = SyncMergeEngine.reconcileChangesMadeDuringSync(
            currentPages: data.pages,
            synchronizedPages: result.pages,
            sourcePages: sourceSnapshot.pages
        )

        objectWillChange.send()
        data.pages = reconciliation.pages
        _ = dayPageController.ensurePage(dateKey: currentDateKey, in: &data)
        try dataStore.save(data)
        lastErrorMessage = nil

        if !reconciliation.dateKeysToUpload.isEmpty {
            cloudSyncCoordinator?.schedule(snapshot: cloudSyncSnapshot())
        }
    }
}
