import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var stickyWindowController: StickyWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let dateKeyService = DateKeyService()
        let dataStore = JSONAppDataStore()
        let appState = AppState(dataStore: dataStore, dateKeyService: dateKeyService)
        let stickyWindowController = StickyWindowController(appState: appState)

        self.appState = appState
        self.stickyWindowController = stickyWindowController

        stickyWindowController.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.saveImmediately()
    }
}

