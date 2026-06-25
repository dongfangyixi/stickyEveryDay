import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var appState: AppState?
    private var stickyWindowController: StickyWindowController?
    private var helpWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let dateKeyService = DateKeyService()
        let dataStore = JSONAppDataStore()
        let appState = AppState(dataStore: dataStore, dateKeyService: dateKeyService)
        let stickyWindowController = StickyWindowController(appState: appState)

        self.appState = appState
        self.stickyWindowController = stickyWindowController
        AppRuntime.shared.appState = appState

        stickyWindowController.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.saveImmediately()
    }

    func showHelp() {
        if let helpWindowController {
            helpWindowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let appState else {
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DailySticky Help"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: DailyStickyHelpView()
                .environmentObject(appState)
        )
        window.center()

        let controller = NSWindowController(window: window)
        helpWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
