import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var appState: AppState?
    private var stickyWindowController: StickyWindowController?
    private var aboutWindowController: NSWindowController?
    private var helpWindowController: NSWindowController?
    private var quickStartWindowController: NSWindowController?
    private var quickStartSettings: QuickStartSettings?
    private var storageChoiceWindowController: NSWindowController?
    private var noteSearchPanelController: NoteSearchPanelController?
    private var currentNoteFindController: CurrentNoteFindController?
    private var noteSearchAnchorScreenRect: NSRect?
    private var searchShortcutMonitor: Any?
    private var languageCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let dateKeyService = DateKeyService()
        let dataStore = JSONAppDataStore()
        let appState = AppState(
            dataStore: dataStore,
            dateKeyService: dateKeyService,
            cloudSyncService: CloudKitSyncService()
        )
        let currentNoteFindController = CurrentNoteFindController()
        let stickyWindowController = StickyWindowController(
            appState: appState,
            currentNoteFindController: currentNoteFindController,
            onToggleNoteSearch: { [weak self] in
                self?.toggleNoteSearch(anchorScreenRect: nil)
            },
            onNoteSearchAnchorChange: { [weak self] screenRect in
                self?.updateNoteSearchAnchor(screenRect)
            }
        )

        self.appState = appState
        self.stickyWindowController = stickyWindowController
        self.noteSearchPanelController = NoteSearchPanelController(appState: appState)
        self.currentNoteFindController = currentNoteFindController
        AppRuntime.shared.appState = appState
        AppRuntime.shared.language = appState.language
        languageCancellable = appState.$language.sink { [weak self] language in
            AppRuntime.shared.language = language
            self?.refreshLocalizedWindowTitles(language: language)
        }
        installSearchShortcutMonitor()

        stickyWindowController.show()
        showFirstRunExperienceIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appState?.appDidBecomeActive()
    }

    func applicationDidResignActive(_ notification: Notification) {
        appState?.appDidResignActive()
    }

    private func refreshLocalizedWindowTitles(language: AppLanguage) {
        aboutWindowController?.window?.title = language.localized("About Pinaday")
        helpWindowController?.window?.title = language.localized("Pinaday Help")
        quickStartWindowController?.window?.title = language.localized("Pinaday Quick Start")

        DispatchQueue.main.async { [weak self] in
            self?.noteSearchPanelController?.updateLanguage()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        stickyWindowController?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let searchShortcutMonitor {
            NSEvent.removeMonitor(searchShortcutMonitor)
        }
        appState?.saveImmediately()
    }

    func closeActiveWindow() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return
        }

        window.close()
    }

    func showNoteSearch(anchorScreenRect: NSRect? = nil) {
        stickyWindowController?.show()
        if let anchorScreenRect {
            noteSearchAnchorScreenRect = anchorScreenRect
        }
        noteSearchPanelController?.show(
            relativeTo: noteSearchAnchorScreenRect,
            noteWindowFrame: stickyWindowController?.currentWindowFrame
        )
    }

    func showCurrentNoteFind() {
        stickyWindowController?.show()
        currentNoteFindController?.present()
    }

    func toggleNoteSearch(anchorScreenRect: NSRect?) {
        if appState?.isNoteSearchPresented == true {
            dismissNoteSearch()
        } else {
            showNoteSearch(anchorScreenRect: anchorScreenRect)
        }
    }

    func dismissNoteSearch() {
        noteSearchPanelController?.dismiss()
    }

    func updateNoteSearchAnchor(_ screenRect: NSRect) {
        noteSearchAnchorScreenRect = screenRect
    }

    private func installSearchShortcutMonitor() {
        searchShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if CurrentNoteFindShortcut.matches(event) {
                self?.showCurrentNoteFind()
                return nil
            }
            if GoToNoteShortcut.matches(event) {
                self?.showNoteSearch()
                return nil
            }
            return event
        }
    }

    func showAbout() {
        if let aboutWindowController {
            aboutWindowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let appState else {
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = appState.localized("About Pinaday")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: PinadayAboutView()
                .environmentObject(appState)
        )
        window.center()

        let controller = NSWindowController(window: window)
        aboutWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appState.localized("Pinaday Help")
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

    func showQuickStartGuide() {
        showQuickStart()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showFirstRunExperienceIfNeeded() {
        guard let appState else {
            return
        }

        if !appState.hasChosenStorageMode {
            DispatchQueue.main.async { [weak self] in
                self?.showStorageChoice()
            }
        } else {
            showQuickStartIfNeeded()
        }
    }

    private func showStorageChoice() {
        if let storageChoiceWindowController {
            storageChoiceWindowController.window?.makeKeyAndOrderFront(nil)
            return
        }

        guard let appState else {
            return
        }

        let window = QuickStartWindow(
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 330),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = appState.localized("Choose Note Storage")
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: StorageChoiceView { [weak self] storageMode in
                self?.completeStorageChoice(storageMode)
            }
            .environmentObject(appState)
        )
        positionQuickStartWindow(window)

        let controller = NSWindowController(window: window)
        storageChoiceWindowController = controller
        window.orderFrontRegardless()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func completeStorageChoice(_ storageMode: StorageMode) {
        appState?.chooseStorageMode(storageMode)
        storageChoiceWindowController?.close()
        storageChoiceWindowController = nil
        showQuickStartIfNeeded()
    }

    private func showQuickStartIfNeeded() {
        guard let appState,
              appState.hasChosenStorageMode,
              !appState.hasSeenWelcome
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.showQuickStart()
        }
    }

    private func showQuickStart() {
        if let quickStartWindowController {
            quickStartWindowController.window?.makeKeyAndOrderFront(nil)
            return
        }

        guard let appState else {
            return
        }

        let settings = QuickStartSettings()
        quickStartSettings = settings

        let window = QuickStartWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 314),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = appState.localized("Pinaday Quick Start")
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: PinadayQuickStartView(
                settings: settings,
                onClose: { [weak self] in
                    self?.closeQuickStart()
                }
            )
            .environmentObject(appState)
        )
        positionQuickStartWindow(window)

        let controller = NSWindowController(window: window)
        quickStartWindowController = controller
        controller.showWindow(nil)
    }

    private func closeQuickStart() {
        if quickStartSettings?.doNotShowAgain == true {
            appState?.markWelcomeSeen()
        }

        quickStartWindowController?.close()
        quickStartWindowController = nil
        quickStartSettings = nil
    }

    private func positionQuickStartWindow(_ window: NSWindow) {
        guard let noteFrame = stickyWindowController?.currentWindowFrame,
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(noteFrame) }) ?? NSScreen.main
        else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let gap: CGFloat = 16
        let windowSize = window.frame.size
        let rightX = noteFrame.maxX + gap
        let leftX = noteFrame.minX - windowSize.width - gap
        let x = rightX + windowSize.width <= visibleFrame.maxX
            ? rightX
            : max(visibleFrame.minX + gap, leftX)
        let y = min(
            max(visibleFrame.minY + gap, noteFrame.maxY - windowSize.height),
            visibleFrame.maxY - windowSize.height - gap
        )

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

enum CurrentNoteFindShortcut {
    static func matches(_ event: NSEvent) -> Bool {
        matches(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }

    static func matches(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let relevantModifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return charactersIgnoringModifiers?.lowercased() == "f" && relevantModifiers == .command
    }
}

enum GoToNoteShortcut {
    static func matches(_ event: NSEvent) -> Bool {
        matches(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }

    static func matches(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let relevantModifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return charactersIgnoringModifiers?.lowercased() == "p" && relevantModifiers == .command
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === quickStartWindowController?.window else {
            return
        }

        if quickStartSettings?.doNotShowAgain == true {
            appState?.markWelcomeSeen()
        }

        quickStartWindowController = nil
        quickStartSettings = nil
    }
}

private final class QuickStartSettings: ObservableObject {
    @Published var doNotShowAgain = true
}

private final class QuickStartWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private struct StorageChoiceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: StorageMode = .localOnly
    let onContinue: (StorageMode) -> Void

    var body: some View {
        let palette = appState.themePalette

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.localized("Choose where your notes live"))
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text(appState.localized("You can change this later in Settings."))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
            }

            VStack(spacing: 9) {
                StorageChoiceRow(
                    mode: .localOnly,
                    systemImage: "internaldrive.fill",
                    detail: "Notes and images stay on this Mac. Nothing is uploaded to iCloud.",
                    badge: "Recommended for privacy",
                    selection: $selection
                )
                StorageChoiceRow(
                    mode: .iCloud,
                    systemImage: "icloud.fill",
                    detail: "Keep notes and images available on your Apple devices using the same Apple Account.",
                    badge: nil,
                    selection: $selection
                )
            }

            HStack {
                Label(
                    appState.localized("Your notes always remain available offline on this Mac."),
                    systemImage: "lock.shield"
                )
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryText)

                Spacer()

                Button(appState.localized("Continue")) {
                    onContinue(selection)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 468, height: 330)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.separator, lineWidth: 1)
        )
        .foregroundStyle(palette.text)
    }
}

private struct StorageChoiceRow: View {
    let mode: StorageMode
    let systemImage: String
    let detail: String
    let badge: String?
    @Binding var selection: StorageMode
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette
        let isSelected = selection == mode

        Button {
            selection = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(appState.localized(mode.localizationKey))
                            .font(.system(size: 14, weight: .semibold))
                        if let badge {
                            Text(appState.localized(badge))
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 6)
                                .frame(height: 18)
                                .background(
                                    Capsule().fill(palette.accent.opacity(0.14))
                                )
                                .foregroundStyle(palette.accent)
                        }
                    }
                    Text(appState.localized(detail))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryText.opacity(0.7))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.accent.opacity(0.08) : palette.paperInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? palette.accent : palette.separator, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PinadayQuickStartView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var settings: QuickStartSettings
    let onClose: () -> Void

    var body: some View {
        let palette = appState.themePalette

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.localized("Pinaday basics"))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text(appState.localized("A few things to know for a smoother start."))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                QuickStartHeaderDemo()
                QuickStartMarkdownDemo()
                QuickStartSlashDemo()
            }

            HStack(spacing: 12) {
                QuickStartCheckboxToggle(isOn: $settings.doNotShowAgain)

                Spacer()

                Button(appState.localized("Got it")) {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.separator, lineWidth: 1)
        )
        .foregroundStyle(palette.text)
    }
}

private struct QuickStartHeaderDemo: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        QuickStartInstructionRow(
            title: "Move through days",
            detail: "Use the arrows to move between days. A Today button appears whenever you are viewing another date."
        ) {
            HStack(spacing: 6) {
                DemoIconButton(systemName: "chevron.left")
                Text("Jul 9")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(minWidth: 48)
                DemoIconButton(systemName: "chevron.right")
                DemoTextButton(title: "Today")
                DemoIconButton(systemName: "magnifyingglass")
                DemoIconButton(systemName: "pin.fill", isActive: true)
            }
            .foregroundStyle(palette.text)
        }
    }
}

private struct QuickStartSlashDemo: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        VStack(alignment: .leading, spacing: 7) {
            Text(appState.localized("Quick select with /"))
                .font(.system(size: 12, weight: .semibold))

            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 7) {
                    DemoSlashKey()
                    Text(appState.localized("Type / on an empty line to choose a format."))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 3) {
                    DemoMenuItem(title: "Todo list", syntax: "- [ ]")
                    DemoMenuItem(title: "Heading", syntax: "#")
                    DemoMenuItem(title: "Divider", syntax: "---")
                }
                .frame(width: 142)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.paperInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.separator, lineWidth: 1)
        )
    }
}

private struct QuickStartMarkdownDemo: View {
    var body: some View {
        QuickStartInstructionRow(
            title: "Markdown format",
            detail: "Use familiar Markdown: bold text, headings, tasks, dividers, tables, and code blocks."
        ) {
            HStack(spacing: 6) {
                DemoCommandChip(title: "Bold", syntax: "**")
                DemoCommandChip(title: "Heading", syntax: "#")
                DemoCommandChip(title: "Todo", syntax: "- [ ]")
                DemoCommandChip(title: "Divider", syntax: "---")
            }
        }
    }
}

private struct QuickStartInstructionRow<Demo: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var demo: Demo
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        VStack(alignment: .leading, spacing: 7) {
            Text(appState.localized(title))
                .font(.system(size: 12, weight: .semibold))

            demo
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(appState.localized(detail))
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.paperInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.separator, lineWidth: 1)
        )
    }
}

private struct QuickStartCheckboxToggle: View {
    @Binding var isOn: Bool
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isOn ? palette.accent : palette.paperInset)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(isOn ? palette.accent : palette.checkboxBorderNS.color, lineWidth: 1.4)
                        )

                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(palette.checkboxCheckmarkNS))
                    }
                }
                .frame(width: 14, height: 14)

                Text(appState.localized("Don't show again"))
                    .font(.system(size: 12))
            }
            .foregroundStyle(palette.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            appState.localized(
                isOn
                    ? "Pinaday will not show this guide at launch."
                    : "Show this guide again next launch."
            )
        )
    }
}

private struct DemoIconButton: View {
    let systemName: String
    var isActive = false
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isActive ? palette.accent : palette.text)
            .frame(width: 24, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? palette.accent.opacity(0.16) : palette.controlBackground)
            )
    }
}

private struct DemoTextButton: View {
    let title: String
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        Text(appState.localized(title))
            .lineLimit(1)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(palette.text)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.controlBackground)
        )
    }
}

private struct DemoSlashKey: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        Text("/")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.accent)
            .frame(width: 24, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.accent.opacity(0.14))
            )
    }
}

private struct DemoCommandChip: View {
    let title: String
    let syntax: String
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        HStack(spacing: 5) {
            Text(appState.localized(title))
            Text(syntax)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.controlBackground)
        )
    }
}

private struct DemoMenuItem: View {
    let title: String
    let syntax: String
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        HStack(spacing: 6) {
            Text(appState.localized(title))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(syntax)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.controlBackground)
        )
    }
}

private extension NSColor {
    var color: Color {
        Color(self)
    }
}
