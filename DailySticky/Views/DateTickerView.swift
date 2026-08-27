import AppKit
import SwiftUI

enum DateTickerDensity: Equatable {
    case fullFaces
    case numbersOnly
}

enum DateTickerTodayEdge: Equatable {
    case none
    case leading
    case trailing
}

struct DateTickerProjection: Equatable {
    let x: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    let opacity: Double
    let blurRadius: CGFloat
    let angle: CGFloat
    let isVisible: Bool
}

struct DateTickerFacePlacement: Identifiable, Equatable {
    let id: String
    let offset: Int
}

enum DateTickerLayout {
    static let compactHeaderWidth: CGFloat = 400
    static let bandHeight: CGFloat = 40
    static let minimumWidth: CGFloat = 126
    static let maximumWidth: CGFloat = 374
    static let fullFacePitch: CGFloat = 92
    static let compactFacePitch: CGFloat = 46
    static let anglePerDay: CGFloat = 20
    static let dragPointsPerDay: CGFloat = 44
    static let perspective: CGFloat = 300
    static let maximumFaceAngle: CGFloat = 74
    static let maximumReadableFaceAngle: CGFloat = 60
    static let maximumFlickDays = 5
    static let todayTabWidth: CGFloat = 34
    static let clickSecondsPerDay = 0.14

    static func density(forHeaderWidth width: CGFloat) -> DateTickerDensity {
        width <= compactHeaderWidth ? .numbersOnly : .fullFaces
    }

    static func pitch(for density: DateTickerDensity) -> CGFloat {
        density == .fullFaces ? fullFacePitch : compactFacePitch
    }

    static func usesFullLabel(
        density: DateTickerDensity,
        isSelected: Bool
    ) -> Bool {
        density == .fullFaces || isSelected
    }

    static func faceWidth(
        density: DateTickerDensity,
        isSelected: Bool
    ) -> CGFloat {
        usesFullLabel(density: density, isSelected: isSelected)
            ? fullFacePitch
            : compactFacePitch
    }

    static func radius(for density: DateTickerDensity) -> CGFloat {
        let halfFace = pitch(for: density) / 2
        return halfFace / tan(anglePerDay * .pi / 360)
    }

    static func rotation(forDragTranslation translation: CGFloat) -> CGFloat {
        -translation * anglePerDay / dragPointsPerDay
    }

    static func projectedX(
        angle: CGFloat,
        density: DateTickerDensity
    ) -> CGFloat {
        let radius = radius(for: density)
        let radians = angle * .pi / 180
        return (radius * sin(radians) * perspective)
            / (perspective + radius * (1 - cos(radians)))
    }

    static func projection(
        forDayOffset offset: Int,
        visualRotation: CGFloat,
        tickerWidth: CGFloat,
        density: DateTickerDensity
    ) -> DateTickerProjection {
        let angle = CGFloat(offset) * anglePerDay - visualRotation
        let absoluteAngle = abs(angle)
        let radians = angle * .pi / 180
        let cosine = max(cos(radians), 0)
        let radius = radius(for: density)
        let depthScale = perspective
            / (perspective + radius * (1 - cosine))
        let x = projectedX(angle: angle, density: density)
        // The prototype's native 3D/vignette stack fully conceals the face at
        // 60 degrees. Our projected SwiftUI faces need the same explicit rim
        // cutoff so a second, overlapping date cannot leak through the fade.
        let isVisible = absoluteAngle < maximumReadableFaceAngle
            && abs(x) <= (tickerWidth / 2) + pitch(for: density) * 0.35

        return DateTickerProjection(
            x: x,
            scaleX: max(0.05, cosine * depthScale),
            scaleY: depthScale,
            opacity: isVisible ? max(0, pow(cosine, 1.5)) : 0,
            blurRadius: absoluteAngle > 55 ? (absoluteAngle - 55) / 14 : 0,
            angle: angle,
            isVisible: isVisible
        )
    }

    static func edgeFaceAttenuation(
        projectedX: CGFloat,
        tickerWidth: CGFloat,
        density: DateTickerDensity,
        todayEdge: DateTickerTodayEdge
    ) -> Double {
        guard todayEdge != .none else { return 1 }

        let centerX = tickerWidth / 2 + projectedX
        let distanceFromEdge = todayEdge == .leading
            ? centerX
            : tickerWidth - centerX
        let fadeStart = todayTabWidth / 2
        let fadeEnd = todayTabWidth + pitch(for: density) / 2
        let progress = min(max(
            (distanceFromEdge - fadeStart) / (fadeEnd - fadeStart),
            0
        ), 1)
        let easedProgress = progress * progress * (3 - 2 * progress)

        return 0.14 + 0.86 * Double(easedProgress)
    }

    static func handoffAngle(
        tickerWidth: CGFloat,
        density: DateTickerDensity
    ) -> CGFloat {
        let limit = tickerWidth / 2 - 22
        var angle: CGFloat = maximumFaceAngle
        var candidate: CGFloat = 4

        while candidate <= maximumFaceAngle {
            if abs(projectedX(angle: candidate, density: density)) > limit {
                angle = candidate
                break
            }
            candidate += 0.5
        }

        if angle >= 16 {
            angle = max(angle, 16)
        }
        return min(45, angle)
    }

    static func todayEdge(
        tickerWidth: CGFloat,
        currentDayOffsetFromToday: Int,
        visualRotation: CGFloat,
        density: DateTickerDensity
    ) -> DateTickerTodayEdge {
        let todayAngle = -CGFloat(currentDayOffsetFromToday) * anglePerDay
            - visualRotation
        guard abs(todayAngle) >= handoffAngle(
            tickerWidth: tickerWidth,
            density: density
        ) else {
            return .none
        }
        return todayAngle < 0 ? .leading : .trailing
    }

    static func navigationDelta(
        translation: CGFloat,
        predictedTranslation: CGFloat
    ) -> Int {
        let effectiveTranslation = abs(predictedTranslation) > abs(translation)
            ? predictedTranslation
            : translation
        let rawDays = Int((-effectiveTranslation / dragPointsPerDay).rounded())
        return min(max(rawDays, -maximumFlickDays), maximumFlickDays)
    }

    static func preservedRotation(
        visualRotation: CGFloat,
        navigatingBy days: Int
    ) -> CGFloat {
        visualRotation - CGFloat(days) * anglePerDay
    }

    static func clickTargetRotation(navigatingBy days: Int) -> CGFloat {
        CGFloat(days) * anglePerDay
    }

    static func clickAnimationDuration(navigatingBy days: Int) -> TimeInterval {
        Double(abs(days)) * clickSecondsPerDay
    }

    static func clickedDayOffset(
        x: CGFloat,
        width: CGFloat,
        density: DateTickerDensity,
        visualRotation: CGFloat = 0,
        todayDayOffset: Int? = nil
    ) -> Int {
        let targetX = x - width / 2
        let offsets = visibleDayOffsets(
            tickerWidth: width,
            density: density,
            visualRotation: visualRotation,
            todayDayOffset: todayDayOffset
        )
        let faces = offsets.map { offset in
            (
                offset: offset,
                projection: projection(
                    forDayOffset: offset,
                    visualRotation: visualRotation,
                    tickerWidth: width,
                    density: density
                )
            )
        }

        return faces.min { lhs, rhs in
            abs(lhs.projection.x - targetX) < abs(rhs.projection.x - targetX)
        }?.offset ?? 0
    }

    static func visibleDayOffsets(
        tickerWidth: CGFloat,
        density: DateTickerDensity,
        visualRotation: CGFloat,
        todayDayOffset: Int? = nil
    ) -> [Int] {
        let selectedOffset = Int((visualRotation / anglePerDay).rounded())
        let handoff = handoffAngle(tickerWidth: tickerWidth, density: density)

        return Array((selectedOffset - 9)...(selectedOffset + 9)).filter { offset in
            let face = projection(
                forDayOffset: offset,
                visualRotation: visualRotation,
                tickerWidth: tickerWidth,
                density: density
            )
            guard face.isVisible else { return false }
            guard offset == todayDayOffset else { return true }
            return abs(face.angle) < handoff
        }
    }
}

struct DateTickerTheme {
    let bar: Color
    let pill: Color
    let text: Color
    let icon: Color
    let dim: Color
    let line: Color
    let accent: Color
    let pinBackground: Color
    let bandTop: Color
    let bandMiddle: Color
    let bandBottom: Color
    let fade: Color
    let texture: Color
    let rim: Color
    let innerRim: Color
    let lipShadow: Color
    let edgeShade: Color
    let specularHighlight: Color
    let usesVerticalGrooves: Bool

    static func palette(for kind: AppThemeKind) -> DateTickerTheme {
        switch kind {
        case .yellow:
            return DateTickerTheme(
                bar: Color(red: 248 / 255, green: 237 / 255, blue: 180 / 255),
                pill: Color(red: 237 / 255, green: 224 / 255, blue: 160 / 255),
                text: Color(red: 43 / 255, green: 36 / 255, blue: 18 / 255),
                icon: Color(red: 89 / 255, green: 81 / 255, blue: 58 / 255),
                dim: Color(red: 140 / 255, green: 123 / 255, blue: 65 / 255),
                line: Color(red: 96 / 255, green: 84 / 255, blue: 40 / 255).opacity(0.22),
                accent: Color(red: 31 / 255, green: 109 / 255, blue: 126 / 255),
                pinBackground: Color(red: 194 / 255, green: 216 / 255, blue: 211 / 255),
                bandTop: Color(red: 243 / 255, green: 231 / 255, blue: 166 / 255),
                bandMiddle: Color(red: 1, green: 251 / 255, blue: 221 / 255),
                bandBottom: Color(red: 239 / 255, green: 226 / 255, blue: 160 / 255),
                fade: Color(red: 252 / 255, green: 247 / 255, blue: 214 / 255),
                texture: Color(red: 96 / 255, green: 84 / 255, blue: 40 / 255).opacity(0.05),
                rim: Color(red: 96 / 255, green: 84 / 255, blue: 40 / 255).opacity(0.26),
                innerRim: Color.white.opacity(0.45),
                lipShadow: Color(red: 96 / 255, green: 84 / 255, blue: 40 / 255).opacity(0.22),
                edgeShade: Color(red: 96 / 255, green: 84 / 255, blue: 40 / 255).opacity(0.30),
                specularHighlight: Color.white.opacity(0.55),
                usesVerticalGrooves: false
            )
        case .light:
            return DateTickerTheme(
                bar: Color(red: 237 / 255, green: 234 / 255, blue: 224 / 255),
                pill: Color(red: 226 / 255, green: 222 / 255, blue: 209 / 255),
                text: Color(red: 42 / 255, green: 40 / 255, blue: 35 / 255),
                icon: Color(red: 93 / 255, green: 89 / 255, blue: 78 / 255),
                dim: Color(red: 142 / 255, green: 138 / 255, blue: 124 / 255),
                line: Color(red: 40 / 255, green: 38 / 255, blue: 30 / 255).opacity(0.16),
                accent: Color(red: 180 / 255, green: 69 / 255, blue: 58 / 255),
                pinBackground: Color(red: 220 / 255, green: 214 / 255, blue: 196 / 255),
                bandTop: Color(red: 247 / 255, green: 245 / 255, blue: 236 / 255),
                bandMiddle: .white,
                bandBottom: Color(red: 239 / 255, green: 235 / 255, blue: 223 / 255),
                fade: Color(red: 245 / 255, green: 242 / 255, blue: 232 / 255),
                texture: Color(red: 60 / 255, green: 56 / 255, blue: 44 / 255).opacity(0.05),
                rim: Color(red: 40 / 255, green: 38 / 255, blue: 30 / 255).opacity(0.18),
                innerRim: Color.white.opacity(0.70),
                lipShadow: Color(red: 60 / 255, green: 56 / 255, blue: 44 / 255).opacity(0.16),
                edgeShade: Color(red: 60 / 255, green: 56 / 255, blue: 44 / 255).opacity(0.26),
                specularHighlight: Color.white.opacity(0.55),
                usesVerticalGrooves: false
            )
        case .dark:
            return DateTickerTheme(
                bar: Color(red: 43 / 255, green: 38 / 255, blue: 34 / 255),
                pill: Color(red: 58 / 255, green: 52 / 255, blue: 46 / 255),
                text: Color(red: 245 / 255, green: 233 / 255, blue: 208 / 255),
                icon: Color(red: 192 / 255, green: 180 / 255, blue: 156 / 255),
                dim: Color(red: 154 / 255, green: 137 / 255, blue: 116 / 255),
                line: Color(red: 245 / 255, green: 233 / 255, blue: 208 / 255).opacity(0.14),
                accent: Color(red: 232 / 255, green: 180 / 255, blue: 92 / 255),
                pinBackground: Color(red: 74 / 255, green: 63 / 255, blue: 46 / 255),
                bandTop: Color(red: 23 / 255, green: 20 / 255, blue: 18 / 255),
                bandMiddle: Color(red: 44 / 255, green: 38 / 255, blue: 34 / 255),
                bandBottom: Color(red: 20 / 255, green: 17 / 255, blue: 15 / 255),
                fade: Color(red: 23 / 255, green: 20 / 255, blue: 18 / 255),
                texture: Color.black.opacity(0.45),
                rim: Color(red: 11 / 255, green: 10 / 255, blue: 9 / 255),
                innerRim: Color.white.opacity(0.05),
                lipShadow: Color.black.opacity(0.70),
                edgeShade: Color.black.opacity(0.62),
                specularHighlight: Color.white.opacity(0.10),
                usesVerticalGrooves: true
            )
        }
    }
}

struct DateTickerView: View {
    @EnvironmentObject private var appState: AppState
    let headerWidth: CGFloat

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var settleRotation: CGFloat = 0
    @State private var clickNavigationTask: Task<Void, Never>?
    @State private var clickAnimationID: UUID?
    @State private var isHovering = false
    @State private var isHoveringTodayTab = false

    private var density: DateTickerDensity {
        DateTickerLayout.density(forHeaderWidth: headerWidth)
    }

    private var visualRotation: CGFloat {
        settleRotation + DateTickerLayout.rotation(forDragTranslation: dragTranslation)
    }

    private var tickerTheme: DateTickerTheme {
        DateTickerTheme.palette(for: appState.themePalette.kind)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let currentRotation = visualRotation
            let todayEdge = DateTickerLayout.todayEdge(
                tickerWidth: width,
                currentDayOffsetFromToday: appState.currentDayOffsetFromToday,
                visualRotation: currentRotation,
                density: density
            )

            ZStack {
                tickerBackground

                tickerFaces(
                    width: width,
                    visualRotation: currentRotation,
                    todayEdge: todayEdge
                )

                edgeShading

                specularHighlight

                edgeVignette

                if todayEdge != .none {
                    todayTab(edge: todayEdge)
                        .position(
                            x: todayEdge == .leading
                                ? DateTickerLayout.todayTabWidth / 2
                                : width - DateTickerLayout.todayTabWidth / 2,
                            y: DateTickerLayout.bandHeight / 2
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
            .gesture(tickerGesture(width: width, todayEdge: todayEdge))
            .focusable()
            .dateTickerFocusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .left:
                    navigate(by: -1, fromVisualRotation: currentRotation)
                case .right:
                    navigate(by: 1, fromVisualRotation: currentRotation)
                default:
                    break
                }
            }
            .onHover { hovering in
                if hovering, !isHovering {
                    NSCursor.openHand.push()
                } else if !hovering, isHovering {
                    NSCursor.pop()
                }
                isHovering = hovering
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(appState.currentDateTitle)
            .accessibilityHint(appState.localized("Drag or use the arrow keys to move through days"))
            .accessibilityAdjustableAction { direction in
                navigate(
                    by: direction == .increment ? 1 : -1,
                    fromVisualRotation: currentRotation
                )
            }
        }
        .frame(minWidth: DateTickerLayout.minimumWidth)
        .frame(height: DateTickerLayout.bandHeight)
        .onDisappear {
            cancelClickNavigation()
            if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
    }

    @ViewBuilder
    private func tickerFaces(
        width: CGFloat,
        visualRotation: CGFloat,
        todayEdge: DateTickerTodayEdge
    ) -> some View {
        let selectedOffset = Int((visualRotation / DateTickerLayout.anglePerDay).rounded())
        let offsets = DateTickerLayout.visibleDayOffsets(
            tickerWidth: width,
            density: density,
            visualRotation: visualRotation,
            todayDayOffset: -appState.currentDayOffsetFromToday
        )
        let placements = offsets.compactMap { offset -> DateTickerFacePlacement? in
            guard let dateKey = appState.dateKey(
                byAddingDays: offset,
                to: appState.currentDateKey
            ) else {
                return nil
            }
            return DateTickerFacePlacement(id: dateKey, offset: offset)
        }

        ForEach(placements) { placement in
            let dateKey = placement.id
            let offset = placement.offset
            if let content = appState.tickerFaceContent(for: dateKey) {
                let isToday = dateKey == appState.todayDateKey
                let projection = DateTickerLayout.projection(
                    forDayOffset: offset,
                    visualRotation: visualRotation,
                    tickerWidth: width,
                    density: density
                )

                if projection.isVisible {
                    let isSelected = offset == selectedOffset
                    face(
                        content: content,
                        isSelected: isSelected,
                        isToday: isToday
                    )
                    .frame(
                        width: DateTickerLayout.faceWidth(
                            density: density,
                            isSelected: isSelected
                        ),
                        height: DateTickerLayout.bandHeight
                    )
                    .scaleEffect(
                        x: projection.scaleX,
                        y: projection.scaleY,
                        anchor: .center
                    )
                    .position(
                        x: width / 2 + projection.x,
                        y: DateTickerLayout.bandHeight / 2
                    )
                    .opacity(
                        projection.opacity * DateTickerLayout.edgeFaceAttenuation(
                            projectedX: projection.x,
                            tickerWidth: width,
                            density: density,
                            todayEdge: todayEdge
                        )
                    )
                    .blur(radius: projection.blurRadius)
                    .zIndex(100 - Double(abs(projection.angle)))
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var tickerBackground: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: tickerTheme.bandTop, location: 0),
                        .init(color: tickerTheme.bandMiddle, location: 0.46),
                        .init(color: tickerTheme.bandBottom, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Canvas { context, size in
                    var lines = Path()
                    if tickerTheme.usesVerticalGrooves {
                        stride(from: CGFloat(0), through: size.width, by: 12).forEach { x in
                            lines.move(to: CGPoint(x: x, y: 0))
                            lines.addLine(to: CGPoint(x: x, y: size.height))
                        }
                    } else {
                        stride(from: CGFloat(0), through: size.height, by: 3).forEach { y in
                            lines.move(to: CGPoint(x: 0, y: y))
                            lines.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    }
                    context.stroke(lines, with: .color(tickerTheme.texture), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .overlay {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [tickerTheme.lipShadow, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: appState.themePalette.kind == .dark ? 8 : 4)

                    Spacer(minLength: 0)

                    LinearGradient(
                        colors: [.clear, tickerTheme.lipShadow],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: appState.themePalette.kind == .dark ? 8 : 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .inset(by: 1)
                    .stroke(tickerTheme.innerRim, lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(tickerTheme.rim, lineWidth: 1)
            }
    }

    private var edgeShading: some View {
        LinearGradient(
            stops: [
                .init(color: tickerTheme.edgeShade, location: 0),
                .init(color: tickerTheme.edgeShade.opacity(0.62), location: 0.11),
                .init(color: tickerTheme.edgeShade.opacity(0.20), location: 0.26),
                .init(color: tickerTheme.edgeShade.opacity(0), location: 0.44),
                .init(color: tickerTheme.edgeShade.opacity(0), location: 0.56),
                .init(color: tickerTheme.edgeShade.opacity(0.20), location: 0.74),
                .init(color: tickerTheme.edgeShade.opacity(0.62), location: 0.89),
                .init(color: tickerTheme.edgeShade, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .allowsHitTesting(false)
    }

    private var specularHighlight: some View {
        GeometryReader { proxy in
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [tickerTheme.specularHighlight, .clear],
                        center: .bottom,
                        startRadius: 0,
                        endRadius: proxy.size.width * 0.32
                    )
                )
                .frame(
                    width: proxy.size.width * 0.64,
                    height: DateTickerLayout.bandHeight * 0.34
                )
                .position(
                    x: proxy.size.width / 2,
                    y: 3 + DateTickerLayout.bandHeight * 0.17
                )
        }
        .allowsHitTesting(false)
    }

    private var edgeVignette: some View {
        LinearGradient(
            stops: [
                .init(color: tickerTheme.fade.opacity(0.95), location: 0),
                .init(color: tickerTheme.fade.opacity(0.45), location: 0.08),
                .init(color: tickerTheme.fade.opacity(0), location: 0.24),
                .init(color: tickerTheme.fade.opacity(0), location: 0.76),
                .init(color: tickerTheme.fade.opacity(0.45), location: 0.92),
                .init(color: tickerTheme.fade.opacity(0.95), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func face(
        content: DateTickerFaceContent,
        isSelected: Bool,
        isToday: Bool
    ) -> some View {
        if !DateTickerLayout.usesFullLabel(
            density: density,
            isSelected: isSelected
        ) {
            Text(content.day)
                .font(.system(
                    size: 15,
                    weight: .medium,
                    design: .monospaced
                ))
                .foregroundStyle(isToday ? tickerTheme.accent : tickerTheme.text)
        } else {
            HStack(
                alignment: .firstTextBaseline,
                spacing: 4
            ) {
                Text(content.weekday)
                    .font(.system(
                        size: density == .numbersOnly ? 8 : 8.5,
                        weight: .medium,
                        design: .monospaced
                    ))
                    .foregroundStyle(isToday ? tickerTheme.accent : tickerTheme.dim)
                    .opacity(isSelected ? 1 : 0.72)
                    .fixedSize(horizontal: true, vertical: false)

                Text(content.day)
                    .font(.system(
                        size: density == .numbersOnly ? 14 : 15,
                        weight: isSelected ? .bold : .medium,
                        design: .monospaced
                    ))
                    .foregroundStyle(isToday ? tickerTheme.accent : tickerTheme.text)
                    .fixedSize(horizontal: true, vertical: false)

                Text(content.month)
                    .font(.system(
                        size: density == .numbersOnly ? 8 : 8.5,
                        weight: .medium,
                        design: .monospaced
                    ))
                    .foregroundStyle(isToday ? tickerTheme.accent : tickerTheme.dim)
                    .opacity(isSelected ? 1 : 0.72)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func todayTab(edge: DateTickerTodayEdge) -> some View {
        VStack(spacing: 1) {
            Text(appState.localized("Today").uppercased(with: appState.language.locale))
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            Text(appState.tickerFaceContent(for: appState.todayDateKey)?.day ?? "")
                .font(.system(
                    size: 15,
                    weight: isHoveringTodayTab ? .bold : .semibold,
                    design: .monospaced
                ))
        }
        .foregroundStyle(tickerTheme.accent)
        .frame(width: DateTickerLayout.todayTabWidth, height: DateTickerLayout.bandHeight)
        .background(
            LinearGradient(
                colors: [
                    tickerTheme.accent.opacity(isHoveringTodayTab ? 0.19 : 0.125),
                    tickerTheme.accent.opacity(0.04)
                ],
                startPoint: edge == .leading ? .leading : .trailing,
                endPoint: edge == .leading ? .trailing : .leading
            )
        )
        .overlay(alignment: edge == .leading ? .leading : .trailing) {
            Rectangle()
                .fill(tickerTheme.accent)
                .frame(width: 2)
        }
        .onHover { isHoveringTodayTab = $0 }
        .accessibilityLabel(appState.localized("Back to today"))
    }

    private func tickerGesture(
        width: CGFloat,
        todayEdge: DateTickerTodayEdge
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.width
                if abs(value.translation.width) > 2 {
                    NSCursor.closedHand.set()
                }
            }
            .onChanged { value in
                if abs(value.translation.width) > 2 {
                    cancelClickNavigation()
                }
            }
            .onEnded { value in
                if isHovering {
                    NSCursor.openHand.set()
                }

                let endRotation = settleRotation
                    + DateTickerLayout.rotation(forDragTranslation: value.translation.width)
                if abs(value.translation.width) < 4,
                   abs(value.translation.height) < 4 {
                    handleClick(
                        x: value.location.x,
                        width: width,
                        todayEdge: todayEdge,
                        visualRotation: endRotation
                    )
                    return
                }

                let delta = DateTickerLayout.navigationDelta(
                    translation: value.translation.width,
                    predictedTranslation: value.predictedEndTranslation.width
                )
                navigate(by: delta, fromVisualRotation: endRotation)
            }
    }

    private func handleClick(
        x: CGFloat,
        width: CGFloat,
        todayEdge: DateTickerTodayEdge,
        visualRotation: CGFloat
    ) {
        if todayEdge == .leading, x <= DateTickerLayout.todayTabWidth {
            navigate(
                by: -appState.currentDayOffsetFromToday,
                fromVisualRotation: visualRotation
            )
            return
        }
        if todayEdge == .trailing, x >= width - DateTickerLayout.todayTabWidth {
            navigate(
                by: -appState.currentDayOffsetFromToday,
                fromVisualRotation: visualRotation
            )
            return
        }

        animateClickNavigation(
            by: DateTickerLayout.clickedDayOffset(
                x: x,
                width: width,
                density: density,
                visualRotation: visualRotation,
                todayDayOffset: -appState.currentDayOffsetFromToday
            ),
            fromVisualRotation: visualRotation
        )
    }

    private func animateClickNavigation(
        by days: Int,
        fromVisualRotation visualRotation: CGFloat
    ) {
        cancelClickNavigation()

        guard days != 0,
              let targetDateKey = appState.dateKey(
                byAddingDays: days,
                to: appState.currentDateKey
              )
        else {
            springToRest()
            return
        }

        let targetRotation = DateTickerLayout.clickTargetRotation(
            navigatingBy: days
        )
        let duration = DateTickerLayout.clickAnimationDuration(
            navigatingBy: days
        )
        let animationID = UUID()
        clickAnimationID = animationID

        clickNavigationTask = Task { @MainActor in
            let startTime = ProcessInfo.processInfo.systemUptime

            while !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                let progress = min(max(elapsed / duration, 0), 1)
                settleRotation = visualRotation
                    + (targetRotation - visualRotation) * CGFloat(progress)

                if progress >= 1 {
                    break
                }
                try? await Task.sleep(nanoseconds: 8_333_333)
            }

            guard !Task.isCancelled, clickAnimationID == animationID else {
                return
            }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                appState.openDate(targetDateKey)
                settleRotation = 0
            }
            clickAnimationID = nil
            clickNavigationTask = nil
        }
    }

    private func navigate(by days: Int, fromVisualRotation visualRotation: CGFloat) {
        cancelClickNavigation()
        guard days != 0,
              let targetDateKey = appState.dateKey(
                byAddingDays: days,
                to: appState.currentDateKey
              )
        else {
            springToRest()
            return
        }

        let preservedRotation = DateTickerLayout.preservedRotation(
            visualRotation: visualRotation,
            navigatingBy: days
        )
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            settleRotation = preservedRotation
            appState.openDate(targetDateKey)
        }

        DispatchQueue.main.async {
            springToRest()
        }
    }

    private func springToRest() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            settleRotation = 0
        }
    }

    private func cancelClickNavigation() {
        clickNavigationTask?.cancel()
        clickNavigationTask = nil
        clickAnimationID = nil
    }
}

private extension View {
    @ViewBuilder
    func dateTickerFocusEffectDisabled() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}
