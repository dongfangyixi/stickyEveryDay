import SwiftUI

struct IOSSearchView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = NoteSearchController()

    private var palette: AppTheme.Palette {
        appState.themePalette
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(palette.secondaryText)
                    TextField(
                        appState.localized("Search notes or enter a date"),
                        text: $controller.query
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(appState.localized("Search notes or enter a date"))

                    if !controller.query.isEmpty {
                        Button {
                            controller.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(palette.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                Group {
                    if controller.query.isEmpty {
                        ContentUnavailableView(
                            "Search notes",
                            systemImage: "magnifyingglass",
                            description: Text("Search note text, image text, or enter a date.")
                        )
                    } else if controller.results.isEmpty && !controller.isIndexingImageText {
                        ContentUnavailableView.search(text: controller.query)
                    } else {
                        List(controller.results) { result in
                            Button {
                                _ = appState.openSearchResult(result, query: controller.query)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Label(
                                            appState.displayTitle(for: result.dateKey),
                                            systemImage: result.kind == .date ? "calendar" : "doc.text"
                                        )
                                        .font(.headline)
                                        Spacer()
                                        if result.matchingLineCount > 0 {
                                            Text(result.matchCountLabel(language: appState.language))
                                                .font(.caption)
                                                .foregroundStyle(palette.secondaryText)
                                        }
                                    }
                                    if !result.snippet.isEmpty {
                                        Text(result.snippet)
                                            .font(.subheadline)
                                            .foregroundStyle(palette.text)
                                            .lineLimit(3)
                                    }
                                    if case .image = result.source {
                                        Label("Image text", systemImage: "text.viewfinder")
                                            .font(.caption)
                                            .foregroundStyle(palette.accent)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(palette.paperInset)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .background(palette.paper)
            .navigationTitle(appState.localized("Search Notes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if controller.isIndexingImageText {
                    ToolbarItem(placement: .status) {
                        ProgressView()
                            .accessibilityLabel(appState.localized("Searching image text"))
                    }
                }
            }
        }
        .tint(palette.accent)
        .task {
            controller.rebuildIndex(
                with: appState.data.pages,
                locale: appState.language.locale
            )
            controller.setIndexingImageText(true)
            let documents = await OCRSearchIndexer().documents(for: appState.data.pages)
            guard !Task.isCancelled else { return }
            controller.rebuildIndex(with: documents, locale: appState.language.locale)
            controller.setIndexingImageText(false)
        }
    }
}
