import SwiftUI

struct StickyRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            DateHeaderView()

            Divider()
                .overlay(AppTheme.separator)

            DailyNoteEditorView()
        }
        .frame(minWidth: 320, minHeight: 280)
        .background(AppTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .background(Color.clear)
        .foregroundStyle(AppTheme.text)
    }
}
