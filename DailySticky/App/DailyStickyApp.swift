import ServiceManagement
import SwiftUI

@MainActor
final class AppRuntime: ObservableObject {
    static let shared = AppRuntime()

    @Published var appState: AppState?
    @Published var language: AppLanguage = .english

    private init() {}
}

@main
struct DailyStickyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime.shared

    var body: some Scene {
        Settings {
            Group {
                if let appState = runtime.appState {
                    SettingsView()
                        .environmentObject(appState)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 420)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(localized("About Pinaday")) {
                    appDelegate.showAbout()
                }
            }

            CommandMenu(localized("File")) {
                Button(localized("Close Window")) {
                    appDelegate.closeActiveWindow()
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandGroup(after: .toolbar) {
                Divider()

                Button(localized("Zoom In")) {
                    appDelegate.zoomNoteIn()
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button(localized("Zoom Out")) {
                    appDelegate.zoomNoteOut()
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button(localized("Actual Size")) {
                    appDelegate.resetNoteZoom()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }

            CommandGroup(replacing: .help) {
                Button(localized("Pinaday Quick Start")) {
                    appDelegate.showQuickStartGuide()
                }

                Button(localized("Pinaday Help")) {
                    appDelegate.showHelp()
                }
                .keyboardShortcut("?", modifiers: [.command])
            }

            CommandGroup(after: .textEditing) {
                Divider()

                Button(localized("Find in Note")) {
                    appDelegate.showCurrentNoteFind()
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button(localized("Go to Note")) {
                    appDelegate.showNoteSearch()
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
        }
    }

    private func localized(_ key: String) -> String {
        runtime.language.localized(key)
    }
}

struct PinadayAboutView: View {
    @EnvironmentObject private var appState: AppState

    private let feedbackEmail = "xuluthebest@gmail.com"

    var body: some View {
        let palette = appState.themePalette

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Pinaday")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text(appState.localized("A daily Markdown sticky note."))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondaryText)
                    Text(versionText)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label(appState.localized("Feedback"), systemImage: "envelope")
                    .font(.system(size: 14, weight: .semibold))

                Text(appState.localized("Found an issue or have an idea? Send a note directly to the developer."))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        sendFeedback()
                    } label: {
                        Label(appState.localized("Send Feedback"), systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)

                    Text(feedbackEmail)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 420, height: 300, alignment: .topLeading)
        .background(palette.paper)
        .foregroundStyle(palette.text)
    }

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? ""

        let label = appState.localized("Version")
        return build.isEmpty ? "\(label) \(version)" : "\(label) \(version) (\(build))"
    }

    private func sendFeedback() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Pinaday Feedback")
        ]

        guard let url = components.url else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var opensAtLogin = LaunchAtLoginService.isEnabled
    @State private var launchAtLoginMessage = ""
    @State private var launchAtLoginError: String?

    var body: some View {
        let palette = appState.themePalette
        let opacityPercent = Int(round(appState.noteOpacity * 100))

        VStack(alignment: .leading, spacing: 18) {
            Text(appState.localized("Settings"))
                .font(.system(size: 20, weight: .semibold))

            HStack(spacing: 14) {
                Text(appState.localized("Language"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Menu {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            appState.updateLanguage(language)
                        } label: {
                            if language == appState.language {
                                Label(language.displayName, systemImage: "checkmark")
                            } else {
                                Text(language.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(appState.language.displayName)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 10)
                    .frame(width: 190, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(palette.controlBackground)
                    )
                    .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(appState.localized("Language"))
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(appState.localized("Theme"))
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 10) {
                    ForEach(AppThemeKind.allCases) { theme in
                        Button {
                            appState.updateTheme(theme)
                        } label: {
                            ThemePreviewCard(
                                palette: AppTheme.palette(for: theme),
                                isSelected: appState.theme == theme
                            )
                        }
                        .buttonStyle(.plain)
                        .help(appState.localized(theme.localizationKey))
                    }
                }
            }

            Divider()

            StorageSyncSettingsSection()

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Toggle(
                    appState.localized("Keep sticky note above other windows"),
                    isOn: Binding(
                        get: { appState.isPinned },
                        set: { appState.updatePinned($0) }
                    )
                )
                .toggleStyle(SettingsSwitchToggleStyle(palette: palette))

                VStack(alignment: .leading, spacing: 5) {
                    Toggle(
                        appState.localized("Open Pinaday at login"),
                        isOn: Binding(
                            get: { opensAtLogin },
                            set: { updateOpenAtLogin($0) }
                        )
                    )
                    .toggleStyle(SettingsSwitchToggleStyle(palette: palette))

                    Text(launchAtLoginError ?? launchAtLoginMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(launchAtLoginError == nil ? palette.secondaryText : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appState.localized("Sticky note opacity"))
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(opacityPercent)%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(palette.secondaryText)
                    }

                    Slider(
                        value: Binding(
                            get: { appState.noteOpacity },
                            set: { appState.updateNoteOpacity($0) }
                        ),
                        in: 0...1
                    )
                    .tint(palette.accent)
                }
            }
        }
        .padding(24)
        .background(palette.paper)
        .foregroundStyle(palette.text)
        .onAppear {
            refreshOpenAtLoginState()
        }
        .onChange(of: appState.language) { _ in
            refreshOpenAtLoginState()
        }
    }

    private func refreshOpenAtLoginState() {
        opensAtLogin = LaunchAtLoginService.isEnabled
        launchAtLoginMessage = LaunchAtLoginService.statusMessage(language: appState.language)
        launchAtLoginError = nil
    }

    private func updateOpenAtLogin(_ isEnabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(isEnabled)
            opensAtLogin = LaunchAtLoginService.isEnabled
            launchAtLoginMessage = LaunchAtLoginService.statusMessage(language: appState.language)
            launchAtLoginError = nil
        } catch {
            opensAtLogin = LaunchAtLoginService.isEnabled
            launchAtLoginMessage = LaunchAtLoginService.statusMessage(language: appState.language)
            launchAtLoginError = error.localizedDescription
        }
    }
}

private struct StorageSyncSettingsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        VStack(alignment: .leading, spacing: 10) {
            Text(appState.localized("Storage & Sync"))
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 8) {
                ForEach(StorageMode.allCases) { mode in
                    StorageModeButton(mode: mode)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: syncStatusIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(syncStatusColor(palette: palette))
                Text(syncStatusText)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if appState.storageMode == .iCloud {
                    Button(appState.localized("Sync Now")) {
                        appState.syncNow()
                    }
                    .buttonStyle(SettingsActionButtonStyle(palette: palette))
                    .disabled(isSyncBusy)
                }
            }

            Text(appState.localized("Pinaday always saves a local offline copy first."))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondaryText)
        }
    }

    private var isSyncBusy: Bool {
        appState.cloudSyncStatus == .checkingAccount || appState.cloudSyncStatus == .syncing
    }

    private var syncStatusIcon: String {
        switch appState.cloudSyncStatus {
        case .localOnly: return "internaldrive.fill"
        case .checkingAccount, .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .upToDate: return "checkmark.icloud.fill"
        case .offline: return "icloud.slash"
        case .accountUnavailable, .capabilityUnavailable, .failed:
            return "exclamationmark.icloud.fill"
        }
    }

    private func syncStatusColor(palette: AppTheme.Palette) -> Color {
        switch appState.cloudSyncStatus {
        case .accountUnavailable, .capabilityUnavailable, .failed: return .red
        default: return palette.accent
        }
    }

    private var syncStatusText: String {
        switch appState.cloudSyncStatus {
        case .localOnly:
            return appState.localized("Stored only on this Mac")
        case .checkingAccount:
            return appState.localized("Checking iCloud account...")
        case .syncing:
            return appState.localized("Syncing...")
        case .upToDate:
            return appState.localized("Up to date")
        case .offline:
            return appState.localized("Offline. Changes will sync when the connection returns.")
        case .accountUnavailable:
            return appState.localized("Sign in to iCloud in System Settings to sync.")
        case .capabilityUnavailable:
            return appState.localized("iCloud sync is unavailable in this build.")
        case let .failed(message):
            return String(
                format: appState.localized("Sync couldn't finish: %@"),
                locale: appState.language.locale,
                message
            )
        }
    }
}

private struct StorageModeButton: View {
    @EnvironmentObject private var appState: AppState
    let mode: StorageMode

    var body: some View {
        let palette = appState.themePalette
        let isSelected = appState.storageMode == mode

        Button {
            appState.chooseStorageMode(mode)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: mode == .localOnly ? "internaldrive.fill" : "icloud.fill")
                    .font(.system(size: 12, weight: .medium))
                Text(appState.localized(mode.localizationKey))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? palette.accent : palette.text)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? palette.accent.opacity(0.10) : palette.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? palette.accent : palette.separator, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ThemePreviewCard: View {
    let palette: AppTheme.Palette
    let isSelected: Bool
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 9, height: 9)
                Text(appState.localized(palette.kind.localizationKey))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.text)
            }

            VStack(alignment: .leading, spacing: 5) {
                Capsule()
                    .fill(palette.text)
                    .frame(width: 56, height: 5)
                Capsule()
                    .fill(palette.secondaryText)
                    .frame(width: 42, height: 5)
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(palette.secondaryText, lineWidth: 1.2)
                        .frame(width: 12, height: 12)
                    Capsule()
                        .fill(palette.completedText)
                        .frame(width: 34, height: 5)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.paperInset)
            )
        }
        .padding(10)
        .frame(width: 118, height: 100, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? palette.accent : palette.separator, lineWidth: isSelected ? 2 : 1)
        )
    }
}

struct DailyStickyHelpView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.localized("Pinaday Help"))
                        .font(.system(size: 24, weight: .semibold))
                    Text(appState.localized("A daily Markdown sticky note with checkable tasks, pasted images, and one note per date."))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HelpSection(title: "Daily Pages") {
                    HelpLine(
                        "Move between days",
                        detail: "Use the left and right arrow buttons in the header."
                    )
                    HelpLine(
                        "Back to today",
                        detail: "A Today button appears only when you are viewing another date."
                    )
                    HelpLine(
                        "Pinned note",
                        detail: "Use the pin button to keep the sticky note above other windows."
                    )
                }

                HelpSection(title: "Find and Go To") {
                    HelpLine(
                        "Find in this note",
                        detail: "Press Cmd-F to find text in the note you are viewing. Each match is highlighted and brought into view.",
                        syntax: "Cmd-F"
                    )
                    HelpLine(
                        "Move through matches",
                        detail: "Use the arrow buttons or press Return to move through matches. Escape clears the query first, then closes Find."
                    )
                    HelpLine(
                        "Find text in images",
                        detail: "Find also searches recognized text in pasted images and scrolls to the matching text."
                    )
                    HelpLine(
                        "Go to any note",
                        detail: "Press Cmd-P to search every day by note content or date. Use Up and Down, then Return to open a result.",
                        syntax: "Cmd-P"
                    )
                    HelpLine(
                        "Search by date",
                        detail: "Type a date such as Aug 12. Go to Note supports fuzzy matching across Latin, Chinese, Japanese, and Korean text."
                    )
                    HelpLine(
                        "Return to your day",
                        detail: "After opening a Go to result, use the return-date chip in the header to go back to the day where you started."
                    )
                }

                HelpSection(title: "Markdown Basics") {
                    HelpLine("Bold", syntax: "**text**")
                    HelpLine("Italic", syntax: "*text*")
                    HelpLine("Headings", syntax: "#, ##, ###, ####")
                    HelpLine("Inline code", syntax: "`code`")
                    HelpLine("Strikethrough", syntax: "~~done~~")
                    HelpLine("Quote", syntax: "> text")
                    HelpLine("Divider", syntax: "---")
                }

                HelpSection(title: "Lists and Tasks") {
                    HelpLine(
                        "Todo list",
                        detail: "Click the checkbox to toggle it. The standard unchecked syntax is - [ ].",
                        syntax: "- [ ] task"
                    )
                    HelpLine(
                        "Completed todo",
                        detail: "Completed tasks use x inside the brackets.",
                        syntax: "- [x] task"
                    )
                    HelpLine(
                        "Nested todos",
                        detail: "Tab moves a task in one level. Shift-Tab moves it back out."
                    )
                    HelpLine(
                        "Continue a list",
                        detail: "Return creates the next todo, bullet, number, quote, or code line."
                    )
                    HelpLine(
                        "Soft line",
                        detail: "Shift-Return adds a continuation line without creating a new checkbox or marker."
                    )
                    HelpLine("Bulleted list", syntax: "- item")
                    HelpLine("Numbered list", syntax: "1. item")
                }

                HelpSection(title: "Editing") {
                    HelpLine(
                        "Zoom note content",
                        detail: "Use Cmd-Plus and Cmd-Minus, or pinch on a trackpad. The note reflows without changing the window or header.",
                        syntax: "Cmd-+ / Cmd--"
                    )
                    HelpLine(
                        "Actual Size",
                        detail: "Press Cmd-0 to return note content to 100%.",
                        syntax: "Cmd-0"
                    )
                    HelpLine(
                        "Undo and redo",
                        detail: "Use Cmd-Z to undo and Shift-Cmd-Z to redo."
                    )
                    HelpLine(
                        "Cut current line",
                        detail: "If no text is selected, Cmd-X cuts the whole line where the caret is."
                    )
                    HelpLine(
                        "Copy and paste tasks",
                        detail: "Task checkbox Markdown is preserved when copying and pasting between days."
                    )
                    HelpLine(
                        "Remove an empty task",
                        detail: "Backspace on an empty todo line removes the checkbox marker."
                    )
                }

                HelpSection(title: "Slash Menu") {
                    HelpLine(
                        "Open the menu",
                        detail: "Type / on an empty line. Use Up and Down, then Return, or click an item."
                    )
                    HelpLine(
                        "Todo list",
                        detail: "Choose Todo list or type /todo and press Return.",
                        syntax: "/todo"
                    )
                    HelpLine(
                        "Headings",
                        detail: "Choose Heading 1-4 or type /h1, /h2, /h3, or /h4.",
                        syntax: "/h2"
                    )
                    HelpLine(
                        "Lists and quote",
                        detail: "Choose Bulleted list, Numbered list, or Quote.",
                        syntax: "/list"
                    )
                    HelpLine(
                        "Code block language",
                        detail: "Type /code plus a language name, then press Return.",
                        syntax: "/code swift"
                    )
                    HelpLine(
                        "Divider",
                        detail: "Choose Divider or type /--- to insert a horizontal line.",
                        syntax: "/---"
                    )
                }

                HelpSection(title: "Images") {
                    HelpLine(
                        "Paste an image",
                        detail: "Copy a screenshot or image, then use Cmd-V in the note."
                    )
                    HelpLine(
                        "Move around an image",
                        detail: "The caret stops before or after the image. One arrow key crosses the image."
                    )
                    HelpLine(
                        "Delete an image",
                        detail: "Put the caret beside it and press Delete or Backspace."
                    )
                    HelpLine(
                        "Resize an image",
                        detail: "Select the image, then drag the middle-right handle to change width."
                    )
                }

                HelpSection(title: "Tables and Code") {
                    HelpLine(
                        "Table",
                        detail: "Tables render when the caret is outside them. When the caret is inside, the table stays raw so you can edit rows and columns.",
                        syntax: "| A | B |"
                    )
                    HelpLine(
                        "Table separator",
                        detail: "The second line marks the header separator.",
                        syntax: "| --- | --- |"
                    )
                    HelpLine(
                        "Code block",
                        detail: "Use fenced Markdown or type /code language. Example: /code swift.",
                        syntax: "```swift"
                    )
                }

                HelpSection(title: "Settings") {
                    HelpLine(
                        "Storage & Sync",
                        detail: "Choose Local only to keep everything on this Mac, or Sync with iCloud to use the same notes on your Apple devices."
                    )
                    HelpLine(
                        "Theme",
                        detail: "Choose Yellow, Light, or Dark in Settings."
                    )
                    HelpLine(
                        "Opacity",
                        detail: "Set the sticky note opacity from fully visible to invisible."
                    )
                    HelpLine(
                        "Window behavior",
                        detail: "Pinned state, window size, and position are saved automatically."
                    )
                    HelpLine(
                        "Open at login",
                        detail: "Turn on Open Pinaday at login to start the note automatically when you sign in."
                    )
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pinadayNativeControlAppearance(palette)
        .frame(width: 540, height: 640)
        .background(palette.paper)
        .foregroundStyle(palette.text)
    }
}

private enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func statusMessage(language: AppLanguage) -> String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return language.localized("Pinaday will open automatically when you sign in.")
        case .notRegistered:
            return language.localized("Pinaday will stay closed until you open it.")
        case .requiresApproval:
            return language.localized("Approve Pinaday in System Settings > General > Login Items.")
        case .notFound:
            return language.localized("Open at login is not available for this build.")
        @unknown default:
            return language.localized("Open at login status is unavailable.")
        }
    }

    static func setEnabled(_ isEnabled: Bool) throws {
        let service = SMAppService.mainApp

        if isEnabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        VStack(alignment: .leading, spacing: 10) {
            Text(appState.localized(title))
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.paperInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.separator, lineWidth: 1)
            )
        }
    }
}

private struct HelpLine: View {
    let text: String
    let detail: String?
    let syntax: String?
    @EnvironmentObject private var appState: AppState

    init(_ text: String, detail: String? = nil, syntax: String? = nil) {
        self.text = text
        self.detail = detail
        self.syntax = syntax
    }

    var body: some View {
        let palette = appState.themePalette

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.localized(text))
                    .font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(appState.localized(detail))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if let syntax {
                Text(syntax)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
