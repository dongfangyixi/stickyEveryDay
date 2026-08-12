import SwiftUI

struct StickyRootView: View {
    @EnvironmentObject private var appState: AppState
    let onToggleNoteSearch: () -> Void
    let onNoteSearchAnchorChange: (NSRect) -> Void

    var body: some View {
        let palette = appState.themePalette

        VStack(spacing: 0) {
            DateHeaderView(
                onToggleNoteSearch: onToggleNoteSearch,
                onNoteSearchAnchorChange: onNoteSearchAnchorChange
            )

            Divider()
                .overlay(palette.separator)

            DailyNoteEditorView()
        }
        .frame(minWidth: 320, minHeight: 280)
        .background(palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.separator, lineWidth: 1)
        )
        .background(Color.clear)
        .foregroundStyle(palette.text)
        .ignoresSafeArea(.container, edges: .top)
    }
}
