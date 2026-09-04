import PhotosUI
import SwiftUI

struct IOSRootView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isSearchPresented = false
    @State private var isSettingsPresented = false
    @State private var focusRequestID = UUID()
    @State private var blurRequestID = UUID()
    @State private var editorCommand: IOSMarkdownCommand?
    @State private var selectedPhoto: PhotosPickerItem?

    private var palette: AppTheme.Palette {
        appState.themePalette
    }

    var body: some View {
        ZStack {
            palette.paper
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Rectangle()
                    .fill(palette.separator)
                    .frame(height: 1)

                IOSNoteEditor(
                    text: Binding(
                        get: { appState.currentPage.noteText },
                        set: appState.updateNoteText
                    ),
                    dateKey: appState.currentDateKey,
                    focusRequestID: focusRequestID,
                    blurRequestID: blurRequestID,
                    command: $editorCommand,
                    palette: palette
                )
            }
            .frame(maxWidth: 900)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IOSFormatBar(
                palette: palette,
                command: $editorCommand,
                selectedPhoto: $selectedPhoto
            )
        }
        .sheet(isPresented: $isSearchPresented) {
            IOSSearchView()
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isSettingsPresented) {
            IOSSettingsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: welcomeBinding) {
            IOSWelcomeView()
                .environmentObject(appState)
                .interactiveDismissDisabled()
        }
        .alert(
            appState.localized("Pinaday could not save your note"),
            isPresented: errorBinding
        ) {
            Button("OK") {
                appState.lastErrorMessage = nil
            }
        } message: {
            Text(appState.lastErrorMessage ?? "")
        }
        .task(id: selectedPhoto) {
            await importSelectedPhoto()
        }
        .onChange(of: appState.hasSeenWelcome) { _, hasSeenWelcome in
            if hasSeenWelcome && appState.currentPage.noteText.isEmpty {
                focusRequestID = UUID()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            IOSDateDialView(
                currentDateKey: appState.currentDateKey,
                todayDateKey: appState.todayDateKey,
                theme: appState.theme,
                faceContent: appState.tickerFaceContent,
                dateKeyByAddingDays: appState.dateKey(byAddingDays:to:),
                dayOffset: { start, end in
                    DateKeyService(locale: appState.language.locale)
                        .dayOffset(from: start, to: end) ?? 0
                },
                onSelectDate: openDate
            )

            Spacer(minLength: 0)

            Button {
                isSearchPresented = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .accessibilityLabel(appState.localized("Search notes"))
            }
            .buttonStyle(IOSHeaderButtonStyle(palette: palette))

            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel(appState.localized("Settings"))
            }
            .buttonStyle(IOSHeaderButtonStyle(palette: palette))
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(palette.paper)
    }

    private var welcomeBinding: Binding<Bool> {
        Binding(
            get: { !appState.hasSeenWelcome || !appState.hasChosenStorageMode },
            set: { _ in }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appState.lastErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appState.lastErrorMessage = nil
                }
            }
        )
    }

    private func openDate(_ dateKey: String) {
        let shouldFocus = appState.data.pages[dateKey]?.noteText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true
        appState.openDate(dateKey)
        if shouldFocus {
            focusRequestID = UUID()
        } else {
            blurRequestID = UUID()
        }
    }

    @MainActor
    private func importSelectedPhoto() async {
        guard let selectedPhoto else { return }
        defer { self.selectedPhoto = nil }

        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                return
            }
            let path = try AttachmentStore.saveImageData(
                data,
                dateKey: appState.currentDateKey
            )
            editorCommand = IOSMarkdownCommand(
                action: .insert("\n![image](\(path))\n")
            )
        } catch {
            appState.lastErrorMessage = error.localizedDescription
        }
    }
}
