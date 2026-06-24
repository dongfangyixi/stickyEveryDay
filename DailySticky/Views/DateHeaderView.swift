import SwiftUI

struct DateHeaderView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appState.goToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(StickyIconButtonStyle())
            .help("Previous day")

            VStack(spacing: 4) {
                Text(appState.currentDateTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if appState.isShowingToday {
                    Text("Today")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.14))
                        )
                } else {
                    Button {
                        appState.jumpToToday()
                    } label: {
                        Text("Back to Today")
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .buttonStyle(StickyTextButtonStyle())
                    .help("Go back to today")
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                appState.goToNextDay()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(StickyIconButtonStyle())
            .help("Next day")

            WindowControlsView()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}
