import SwiftUI

enum IOSDateDialMetrics {
    static let width: CGFloat = 184
    static let height: CGFloat = 40
    static let apertureHeight: CGFloat = 36
    static let cornerRadius: CGFloat = 7
    static let numberPitch: CGFloat = 46
    static let selectedWidth: CGFloat = 92
    static let anglePerDay: CGFloat = 20
    static let dragPointsPerDay: CGFloat = 44
    static let perspective: CGFloat = 300
    static let maximumReadableAngle: CGFloat = 60
    static let maximumFlickDays = 5
    static let todayTabWidth: CGFloat = 34
    static let clickSecondsPerDay = 0.14
    static let todayReturnDuration = 0.34
    static let springLambda: CGFloat = 0.18

    static var radius: CGFloat {
        (numberPitch / 2) / tan(anglePerDay * .pi / 360)
    }

    static func rotation(for translation: CGFloat) -> CGFloat {
        -translation * anglePerDay / dragPointsPerDay
    }

    static func projection(offset: Int, visualRotation: CGFloat) -> IOSDateDialProjection {
        let angle = CGFloat(offset) * anglePerDay - visualRotation
        let radians = angle * .pi / 180
        let cosine = max(cos(radians), 0)
        let depthScale = perspective / (perspective + radius * (1 - cosine))
        let x = (radius * sin(radians) * perspective)
            / (perspective + radius * (1 - cosine))
        let visible = abs(angle) < maximumReadableAngle
            && abs(x) <= width / 2 + numberPitch * 0.35

        return IOSDateDialProjection(
            x: x,
            scaleX: max(0.05, cosine * depthScale),
            scaleY: max(0.72, pow(depthScale, 1.45)),
            opacity: visible ? max(0, pow(cosine, 1.5)) : 0,
            blur: abs(angle) > 55 ? (abs(angle) - 55) / 14 : 0,
            angle: angle,
            isVisible: visible
        )
    }

    static func visibleOffsets(visualRotation: CGFloat, todayOffset: Int) -> [Int] {
        let selected = Int((visualRotation / anglePerDay).rounded())
        return Array((selected - 8)...(selected + 8)).filter { offset in
            let projection = projection(offset: offset, visualRotation: visualRotation)
            guard projection.isVisible else { return false }
            guard offset == todayOffset else { return true }
            return abs(projection.angle) < 37
        }
    }

    static func nearestOffset(x: CGFloat, visualRotation: CGFloat, todayOffset: Int) -> Int {
        let target = x - width / 2
        return visibleOffsets(visualRotation: visualRotation, todayOffset: todayOffset)
            .min {
                abs(projection(offset: $0, visualRotation: visualRotation).x - target)
                    < abs(projection(offset: $1, visualRotation: visualRotation).x - target)
            } ?? 0
    }
}

struct IOSDateDialProjection {
    let x: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    let opacity: Double
    let blur: CGFloat
    let angle: CGFloat
    let isVisible: Bool
}

private struct IOSDateDialTheme {
    let bandTop: Color
    let bandMiddle: Color
    let bandBottom: Color
    let text: Color
    let dim: Color
    let accent: Color
    let rim: Color
    let lip: Color
    let edgeShade: Color
    let specular: Color
    let texture: Color

    static func palette(for kind: AppThemeKind) -> IOSDateDialTheme {
        switch kind {
        case .yellow:
            IOSDateDialTheme(
                bandTop: Color(red: 243 / 255, green: 231 / 255, blue: 166 / 255),
                bandMiddle: Color(red: 1, green: 251 / 255, blue: 221 / 255),
                bandBottom: Color(red: 239 / 255, green: 226 / 255, blue: 160 / 255),
                text: Color(red: 43 / 255, green: 36 / 255, blue: 18 / 255),
                dim: Color(red: 140 / 255, green: 123 / 255, blue: 65 / 255),
                accent: Color(red: 31 / 255, green: 109 / 255, blue: 126 / 255),
                rim: Color(red: 96 / 255, green: 84 / 255, blue: 40 / 255).opacity(0.26),
                lip: Color(red: 96 / 255, green: 84 / 255, blue: 40 / 255).opacity(0.22),
                edgeShade: Color(red: 96 / 255, green: 84 / 255, blue: 40 / 255).opacity(0.30),
                specular: Color.white.opacity(0.55),
                texture: Color(red: 96 / 255, green: 84 / 255, blue: 40 / 255).opacity(0.05)
            )
        case .light:
            IOSDateDialTheme(
                bandTop: Color(red: 247 / 255, green: 245 / 255, blue: 236 / 255),
                bandMiddle: .white,
                bandBottom: Color(red: 239 / 255, green: 235 / 255, blue: 223 / 255),
                text: Color(red: 42 / 255, green: 40 / 255, blue: 35 / 255),
                dim: Color(red: 142 / 255, green: 138 / 255, blue: 124 / 255),
                accent: Color(red: 180 / 255, green: 69 / 255, blue: 58 / 255),
                rim: Color(red: 40 / 255, green: 38 / 255, blue: 30 / 255).opacity(0.18),
                lip: Color(red: 60 / 255, green: 56 / 255, blue: 44 / 255).opacity(0.16),
                edgeShade: Color(red: 60 / 255, green: 56 / 255, blue: 44 / 255).opacity(0.26),
                specular: Color.white.opacity(0.55),
                texture: Color(red: 60 / 255, green: 56 / 255, blue: 44 / 255).opacity(0.05)
            )
        case .dark:
            IOSDateDialTheme(
                bandTop: Color(red: 23 / 255, green: 20 / 255, blue: 18 / 255),
                bandMiddle: Color(red: 44 / 255, green: 38 / 255, blue: 34 / 255),
                bandBottom: Color(red: 20 / 255, green: 17 / 255, blue: 15 / 255),
                text: Color(red: 245 / 255, green: 233 / 255, blue: 208 / 255),
                dim: Color(red: 154 / 255, green: 137 / 255, blue: 116 / 255),
                accent: Color(red: 232 / 255, green: 180 / 255, blue: 92 / 255),
                rim: Color(red: 11 / 255, green: 10 / 255, blue: 9 / 255),
                lip: Color.black.opacity(0.70),
                edgeShade: Color.black.opacity(0.62),
                specular: Color.white.opacity(0.10),
                texture: Color.black.opacity(0.45)
            )
        }
    }
}

struct IOSDateDialView: View {
    let currentDateKey: String
    let todayDateKey: String
    let theme: AppThemeKind
    let faceContent: (String) -> DateTickerFaceContent?
    let dateKeyByAddingDays: (Int, String) -> String?
    let dayOffset: (String, String) -> Int
    let onSelectDate: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visualRotation: CGFloat = 0
    @State private var isDragging = false
    @State private var isAnimating = false
    @State private var animationTask: Task<Void, Never>?

    private var dialTheme: IOSDateDialTheme {
        .palette(for: theme)
    }

    private var todayOffset: Int {
        dayOffset(currentDateKey, todayDateKey)
    }

    var body: some View {
        ZStack {
            drumBackground
            faces
            shading
            todayEdgeTab
        }
        .frame(width: IOSDateDialMetrics.width, height: IOSDateDialMetrics.height)
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .onChange(of: currentDateKey) { _, _ in
            guard !isAnimating else { return }
            visualRotation = 0
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    private var drumBackground: some View {
        RoundedRectangle(cornerRadius: IOSDateDialMetrics.cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [dialTheme.bandTop, dialTheme.bandMiddle, dialTheme.bandBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                VStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { _ in
                        Rectangle()
                            .fill(dialTheme.texture)
                            .frame(height: 0.5)
                    }
                }
                .padding(.vertical, 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: IOSDateDialMetrics.cornerRadius, style: .continuous)
                    .stroke(dialTheme.rim, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(dialTheme.lip).frame(height: 2).blur(radius: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(dialTheme.lip).frame(height: 2).blur(radius: 1)
            }
            .frame(height: IOSDateDialMetrics.apertureHeight)
    }

    private var faces: some View {
        ZStack {
            ForEach(
                IOSDateDialMetrics.visibleOffsets(
                    visualRotation: visualRotation,
                    todayOffset: todayOffset
                ),
                id: \.self
            ) { offset in
                if let dateKey = dateKeyByAddingDays(offset, currentDateKey),
                   let content = faceContent(dateKey) {
                    let projection = IOSDateDialMetrics.projection(
                        offset: offset,
                        visualRotation: visualRotation
                    )
                    let isSelected = abs(projection.angle) < IOSDateDialMetrics.anglePerDay / 2
                    let isToday = dateKey == todayDateKey

                    Button {
                        guard !isDragging, !isAnimating else { return }
                        animateClick(days: offset)
                    } label: {
                        face(content, selected: isSelected, today: isToday)
                    }
                        .buttonStyle(.plain)
                        .frame(
                            width: isSelected
                                ? IOSDateDialMetrics.selectedWidth
                                : IOSDateDialMetrics.numberPitch,
                            height: IOSDateDialMetrics.apertureHeight
                        )
                        .scaleEffect(x: projection.scaleX, y: projection.scaleY)
                        .rotation3DEffect(
                            .degrees(Double(-projection.angle)),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.32
                        )
                        .opacity(projection.opacity)
                        .blur(radius: projection.blur)
                        .offset(x: projection.x)
                        .contentShape(Rectangle())
                        .accessibilityLabel(content.accessibilityTitle)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(height: IOSDateDialMetrics.apertureHeight)
        .clipped()
    }

    @ViewBuilder
    private func face(
        _ content: DateTickerFaceContent,
        selected: Bool,
        today: Bool
    ) -> some View {
        let color = today ? dialTheme.accent : (selected ? dialTheme.text : dialTheme.dim)

        if selected {
            HStack(spacing: 4) {
                if content.order == .monthDayWeekday {
                    Text(content.month)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                    Text(content.day)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(content.weekday)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                } else {
                    Text(content.weekday)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                    Text(content.day)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(content.month)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(color)
            .lineLimit(1)
        } else {
            Text(content.day)
                .font(.system(size: 18, weight: today ? .bold : .medium, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private var shading: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: dialTheme.edgeShade, location: 0),
                    .init(color: dialTheme.edgeShade.opacity(0.62), location: 0.11),
                    .init(color: dialTheme.edgeShade.opacity(0.20), location: 0.26),
                    .init(color: .clear, location: 0.44),
                    .init(color: .clear, location: 0.56),
                    .init(color: dialTheme.edgeShade.opacity(0.20), location: 0.74),
                    .init(color: dialTheme.edgeShade.opacity(0.62), location: 0.89),
                    .init(color: dialTheme.edgeShade, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            RadialGradient(
                colors: [dialTheme.specular, .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: IOSDateDialMetrics.width * 0.32
            )
            .frame(width: IOSDateDialMetrics.width * 0.64, height: 13)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 3)

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [dialTheme.bandMiddle.opacity(0.95), dialTheme.bandMiddle.opacity(0.45), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: IOSDateDialMetrics.width * 0.24)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [.clear, dialTheme.bandMiddle.opacity(0.45), dialTheme.bandMiddle.opacity(0.95)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: IOSDateDialMetrics.width * 0.24)
            }
        }
        .frame(height: IOSDateDialMetrics.apertureHeight)
        .clipShape(RoundedRectangle(cornerRadius: IOSDateDialMetrics.cornerRadius))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var todayEdgeTab: some View {
        let angle = CGFloat(todayOffset) * IOSDateDialMetrics.anglePerDay - visualRotation
        if abs(angle) >= 37, let content = faceContent(todayDateKey) {
            let isLeading = angle < 0
            Button {
                guard !isAnimating else { return }
                animateClick(days: todayOffset, duration: IOSDateDialMetrics.todayReturnDuration)
            } label: {
                VStack(spacing: -1) {
                    Text("TODAY")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                    Text(content.day)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(dialTheme.accent)
            .frame(width: IOSDateDialMetrics.todayTabWidth, height: IOSDateDialMetrics.apertureHeight)
            .background(dialTheme.bandMiddle.opacity(0.94))
            .overlay(alignment: isLeading ? .leading : .trailing) {
                Rectangle().fill(dialTheme.accent).frame(width: 2)
            }
            .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
            .contentShape(Rectangle())
            .accessibilityLabel("Back to today")
            .accessibilityHint(content.accessibilityTitle)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                guard !isAnimating else { return }
                isDragging = true
                visualRotation = IOSDateDialMetrics.rotation(for: value.translation.width)
            }
            .onEnded { value in
                guard !isAnimating else { return }
                let startRotation = IOSDateDialMetrics.rotation(for: value.translation.width)
                let projectedRotation = IOSDateDialMetrics.rotation(
                    for: value.predictedEndTranslation.width
                )
                let currentFace = Int((startRotation / IOSDateDialMetrics.anglePerDay).rounded())
                let projectedFace = Int((projectedRotation / IOSDateDialMetrics.anglePerDay).rounded())
                let days = min(
                    max(projectedFace, currentFace - IOSDateDialMetrics.maximumFlickDays),
                    currentFace + IOSDateDialMetrics.maximumFlickDays
                )
                settleSpring(from: startRotation, days: days)
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard !isDragging, !isAnimating else { return }
                let todayAngle = CGFloat(todayOffset) * IOSDateDialMetrics.anglePerDay
                    - visualRotation
                if abs(todayAngle) >= 37 {
                    let touchesTodayTab = todayAngle < 0
                        ? value.location.x <= IOSDateDialMetrics.todayTabWidth
                        : value.location.x >= IOSDateDialMetrics.width - IOSDateDialMetrics.todayTabWidth
                    if touchesTodayTab {
                        animateClick(
                            days: todayOffset,
                            duration: IOSDateDialMetrics.todayReturnDuration
                        )
                        return
                    }
                }

                let offset = IOSDateDialMetrics.nearestOffset(
                    x: value.location.x,
                    visualRotation: visualRotation,
                    todayOffset: todayOffset
                )
                animateClick(days: offset)
            }
    }

    private func animateClick(days: Int, duration: TimeInterval? = nil) {
        guard days != 0, let targetDate = dateKeyByAddingDays(days, currentDateKey) else {
            return
        }

        animationTask?.cancel()
        isAnimating = true
        let target = CGFloat(days) * IOSDateDialMetrics.anglePerDay
        let resolvedDuration = reduceMotion
            ? 0.01
            : duration ?? Double(abs(days)) * IOSDateDialMetrics.clickSecondsPerDay

        withAnimation(.linear(duration: resolvedDuration)) {
            visualRotation = target
        }
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(resolvedDuration))
            guard !Task.isCancelled else { return }
            completeNavigation(to: targetDate)
        }
    }

    private func settleSpring(from startRotation: CGFloat, days: Int) {
        guard let targetDate = dateKeyByAddingDays(days, currentDateKey) else {
            visualRotation = 0
            isDragging = false
            return
        }

        animationTask?.cancel()
        isAnimating = true
        isDragging = false
        let target = CGFloat(days) * IOSDateDialMetrics.anglePerDay

        animationTask = Task { @MainActor in
            var rotation = startRotation
            for _ in 0..<72 {
                guard !Task.isCancelled else { return }
                rotation += (target - rotation) * IOSDateDialMetrics.springLambda
                visualRotation = rotation
                if abs(target - rotation) < 0.05 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            visualRotation = target
            completeNavigation(to: targetDate)
        }
    }

    private func completeNavigation(to dateKey: String) {
        onSelectDate(dateKey)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visualRotation = 0
            isAnimating = false
            isDragging = false
        }
    }
}
