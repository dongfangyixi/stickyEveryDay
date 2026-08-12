import ServiceManagement
import SwiftUI

@MainActor
final class AppRuntime: ObservableObject {
    static let shared = AppRuntime()

    @Published var appState: AppState?

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
                Button("About Pinaday") {
                    appDelegate.showAbout()
                }
            }

            CommandMenu("File") {
                Button("Close Window") {
                    appDelegate.closeActiveWindow()
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandGroup(replacing: .help) {
                Button("Pinaday Quick Start") {
                    appDelegate.showQuickStartGuide()
                }

                Button("Pinaday Help") {
                    appDelegate.showHelp()
                }
                .keyboardShortcut("?", modifiers: [.command])
            }

            CommandGroup(after: .textEditing) {
                Divider()

                Button("Search Notes") {
                    appDelegate.showNoteSearch()
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
        }
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
                    Text("A daily Markdown sticky note.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondaryText)
                    Text(versionText)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Feedback", systemImage: "envelope")
                    .font(.system(size: 14, weight: .semibold))

                Text("Found an issue or have an idea? Send a note directly to the developer.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        sendFeedback()
                    } label: {
                        Label("Send Feedback", systemImage: "paperplane.fill")
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

        return build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
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
    @State private var launchAtLoginMessage = LaunchAtLoginService.statusMessage
    @State private var launchAtLoginError: String?

    var body: some View {
        let palette = appState.themePalette
        let opacityPercent = Int(round(appState.noteOpacity * 100))

        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 20, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Theme")
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
                        .help(theme.displayName)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Toggle(
                    "Keep sticky note above other windows",
                    isOn: Binding(
                        get: { appState.isPinned },
                        set: { appState.updatePinned($0) }
                    )
                )
                .toggleStyle(SettingsSwitchToggleStyle(palette: palette))

                VStack(alignment: .leading, spacing: 5) {
                    Toggle(
                        "Open Pinaday at login",
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
                        Text("Sticky note opacity")
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
    }

    private func refreshOpenAtLoginState() {
        opensAtLogin = LaunchAtLoginService.isEnabled
        launchAtLoginMessage = LaunchAtLoginService.statusMessage
        launchAtLoginError = nil
    }

    private func updateOpenAtLogin(_ isEnabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(isEnabled)
            opensAtLogin = LaunchAtLoginService.isEnabled
            launchAtLoginMessage = LaunchAtLoginService.statusMessage
            launchAtLoginError = nil
        } catch {
            opensAtLogin = LaunchAtLoginService.isEnabled
            launchAtLoginMessage = LaunchAtLoginService.statusMessage
            launchAtLoginError = error.localizedDescription
        }
    }
}

private struct ThemePreviewCard: View {
    let palette: AppTheme.Palette
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 9, height: 9)
                Text(palette.kind.displayName)
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
                    Text("Pinaday Help")
                        .font(.system(size: 24, weight: .semibold))
                    Text("A daily Markdown sticky note with checkable tasks, pasted images, and one note per date.")
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
                        detail: "The Back to Today control appears only when you are viewing another date."
                    )
                    HelpLine(
                        "Pinned note",
                        detail: "Use the pin button to keep the sticky note above other windows."
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
        .frame(width: 540, height: 640)
        .background(palette.paper)
        .foregroundStyle(palette.text)
    }
}

private enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusMessage: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Pinaday will open automatically when you sign in."
        case .notRegistered:
            return "Pinaday will stay closed until you open it."
        case .requiresApproval:
            return "Approve Pinaday in System Settings > General > Login Items."
        case .notFound:
            return "Open at login is not available for this build."
        @unknown default:
            return "Open at login status is unavailable."
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
            Text(title)
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
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
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
