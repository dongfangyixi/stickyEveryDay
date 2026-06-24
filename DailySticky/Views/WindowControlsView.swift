import SwiftUI

struct WindowControlsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            appState.togglePinned()
        } label: {
            Image(systemName: appState.isPinned ? "pin.fill" : "pin")
        }
        .buttonStyle(StickyIconButtonStyle(isActive: appState.isPinned))
        .help(appState.isPinned ? "Unpin window" : "Pin window")
    }
}

