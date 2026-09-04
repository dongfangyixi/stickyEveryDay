import SwiftUI

struct IOSWelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedStorageMode: StorageMode = .localOnly

    private var palette: AppTheme.Palette {
        appState.themePalette
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(palette.accent)
                        Text("Pinaday")
                            .font(.largeTitle.bold())
                            .foregroundStyle(palette.text)
                        Text(appState.localized("A daily Markdown sticky note."))
                            .font(.title3)
                            .foregroundStyle(palette.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        welcomeRow(
                            icon: "dial.medium",
                            title: appState.localized("Move through days"),
                            detail: dialInstructions
                        )
                        welcomeRow(
                            icon: "textformat",
                            title: appState.localized("Markdown format"),
                            detail: appState.localized(
                                "Use familiar Markdown: bold text, headings, tasks, dividers, tables, and code blocks."
                            )
                        )
                        welcomeRow(
                            icon: "photo.on.rectangle",
                            title: appState.localized("Paste images directly to the note."),
                            detail: "Paste an image or choose one from Photos. Pinaday recognizes image text for search."
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(appState.localized("Storage & Sync"))
                            .font(.headline)
                            .foregroundStyle(palette.text)

                        Picker(appState.localized("Storage & Sync"), selection: $selectedStorageMode) {
                            Text(appState.localized("Local only")).tag(StorageMode.localOnly)
                            Text(appState.localized("Sync with iCloud")).tag(StorageMode.iCloud)
                        }
                        .pickerStyle(.segmented)

                        Text(storageExplanation)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }

                    Button {
                        appState.chooseStorageMode(selectedStorageMode)
                        appState.markWelcomeSeen()
                    } label: {
                        Text(appState.localized("Got it"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }
                .padding(24)
            }
            .background(palette.paper.ignoresSafeArea())
            .navigationTitle(appState.localized("Pinaday basics"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            selectedStorageMode = appState.storageMode
        }
    }

    private func welcomeRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var storageExplanation: String {
        switch selectedStorageMode {
        case .localOnly:
            "Notes stay only on this device. You can enable iCloud later in Settings."
        case .iCloud:
            "Notes and images sync through your private iCloud database and remain available offline."
        }
    }

    private var dialInstructions: String {
        if appState.language == .english {
            return "Drag the date dial to move through days, or tap a visible date to jump to it."
        }
        return appState.localized(
            "Drag the date dial to move through days, or click a visible date to jump to it."
        )
    }
}
