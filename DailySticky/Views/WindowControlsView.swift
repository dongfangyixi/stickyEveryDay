import SwiftUI

struct WindowControlsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        Button {
            appState.togglePinned()
        } label: {
            Image(systemName: appState.isPinned ? "pin.fill" : "pin")
        }
        .buttonStyle(StickyIconButtonStyle(isActive: appState.isPinned, palette: palette))
        .help(appState.isPinned ? "Unpin window" : "Pin window")
    }
}
