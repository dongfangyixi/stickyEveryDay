import SwiftUI

struct CurrentNoteFindBar: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var controller: CurrentNoteFindController

    var body: some View {
        let palette = appState.themePalette

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                SearchQueryField(
                    text: $controller.query,
                    focusRequestID: controller.focusRequestID,
                    palette: palette,
                    placeholder: appState.localized("Find in note"),
                    onMoveSelection: { offset in
                        controller.moveSelection(by: offset)
                    },
                    onSubmit: { searchesBackward in
                        controller.moveSelection(by: searchesBackward ? -1 : 1)
                    },
                    onCancel: {
                        controller.handleEscape()
                    }
                )

                if controller.isIndexingImageText {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(palette.accent)
                        .frame(width: 16, height: 16)
                        .help(appState.localized("Searching image text"))
                }

                Text(controller.positionLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                    .frame(minWidth: 34, alignment: .trailing)
                    .accessibilityLabel(appState.localized("Find result position"))

                findButton(
                    systemName: "chevron.up",
                    help: appState.localized("Previous match"),
                    palette: palette
                ) {
                    controller.moveSelection(by: -1)
                }

                findButton(
                    systemName: "chevron.down",
                    help: appState.localized("Next match"),
                    palette: palette
                ) {
                    controller.moveSelection(by: 1)
                }

                Button {
                    controller.close()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(StickyIconButtonStyle(palette: palette))
                .help(appState.localized("Close find"))
                .accessibilityLabel(appState.localized("Close find"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 38)
            .background(palette.paper)

            Divider()
                .overlay(palette.separator)
        }
    }

    private func findButton(
        systemName: String,
        help: String,
        palette: AppTheme.Palette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(StickyIconButtonStyle(palette: palette))
        .disabled(controller.matches.isEmpty)
        .opacity(controller.matches.isEmpty ? 0.48 : 1)
        .help(help)
        .accessibilityLabel(help)
    }
}
