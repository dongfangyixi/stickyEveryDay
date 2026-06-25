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
            CommandGroup(replacing: .help) {
                Button("DailySticky Help") {
                    appDelegate.showHelp()
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

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
                .toggleStyle(.switch)

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
            VStack(alignment: .leading, spacing: 20) {
                Text("DailySticky Help")
                    .font(.system(size: 24, weight: .semibold))

                HelpSection(title: "Markdown") {
                    HelpLine("**bold**")
                    HelpLine("*italic*")
                    HelpLine("# Heading")
                    HelpLine("`code`")
                    HelpLine("~~done~~")
                }

                HelpSection(title: "Checklist") {
                    HelpLine("- [ ] Task")
                    HelpLine("- [x] Completed task")
                    HelpLine("Tab / Shift-Tab changes task level")
                    HelpLine("Return creates the next task")
                    HelpLine("Shift-Return creates a plain continuation line")
                }

                HelpSection(title: "Navigation") {
                    HelpLine("Use the arrow buttons to move by day")
                    HelpLine("Back to Today appears when another day is open")
                    HelpLine("The pin button keeps the note above other windows")
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 520)
        .background(palette.paper)
        .foregroundStyle(palette.text)
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
    }
}

private struct HelpLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .textSelection(.enabled)
    }
}
