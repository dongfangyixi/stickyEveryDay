import SwiftUI

struct WindowControlsView: View {
    @EnvironmentObject private var appState: AppState
    var controlSize: CGFloat = StickyHeaderControlMetrics.height
    var cornerRadius: CGFloat = StickyHeaderControlMetrics.cornerRadius

    var body: some View {
        let headerTheme = DateTickerTheme.palette(for: appState.themePalette.kind)

        Button {
            appState.togglePinned()
        } label: {
            Image(systemName: appState.isPinned ? "pin.fill" : "pin")
        }
        .buttonStyle(
            TickerHeaderControlButtonStyle(
                background: headerTheme.pinBackground,
                foreground: headerTheme.accent,
                size: controlSize,
                cornerRadius: cornerRadius
            )
        )
        .help(
            appState.localized(appState.isPinned ? "Unpin window" : "Pin window")
        )
    }
}
