import SwiftUI

struct DateHeaderView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let palette = appState.themePalette

        HStack(spacing: 8) {
            Button {
                appState.goToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(StickyIconButtonStyle(palette: palette))
            .help("Previous day")

            ViewThatFits(in: .horizontal) {
                Text(appState.currentDateTitle)
                Text(appState.currentCompactDateTitle)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .center)

            if !appState.isShowingToday {
                Button {
                    appState.jumpToToday()
                } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            Text("Back to Today")
                                .lineLimit(1)
                            TodayCalendarIcon()
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "return")
                            TodayCalendarIcon()
                        }
                    }
                }
                .buttonStyle(StickyTextButtonStyle(palette: palette))
                .accessibilityLabel("Back to Today")
                .help("Back to today")
            }

            Button {
                appState.goToNextDay()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(StickyIconButtonStyle(palette: palette))
            .help("Next day")

            WindowControlsView()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct TodayCalendarIcon: View {
    private var dayNumber: String {
        let day = Calendar.autoupdatingCurrent.component(.day, from: Date())
        return "\(day)"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                .stroke(lineWidth: 1.55)
                .frame(width: 13.4, height: 11.4)
                .offset(y: 1.35)

            Path { path in
                path.move(to: CGPoint(x: 4.3, y: 1.2))
                path.addLine(to: CGPoint(x: 4.3, y: 4.15))
                path.move(to: CGPoint(x: 10.7, y: 1.2))
                path.addLine(to: CGPoint(x: 10.7, y: 4.15))
                path.move(to: CGPoint(x: 1.3, y: 5.35))
                path.addLine(to: CGPoint(x: 13.7, y: 5.35))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round))

            Text(dayNumber)
                .font(.system(size: 6.7, weight: .black, design: .rounded))
                .monospacedDigit()
                .offset(y: 3.1)
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }
}
