import AppKit
import XCTest
@testable import Pinaday

final class DateTickerTests: XCTestCase {
    func testStickyWindowAllowsOnlyExplicitWindowMovement() {
        let window = StickyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(window.isMovable)
        XCTAssertFalse(window.isMovableByWindowBackground)

        let header = NSView(frame: window.contentView?.bounds ?? .zero)
        let dial = NSView(frame: NSRect(x: 8, y: 8, width: 374, height: 40))
        let dragRegion = WindowDragNSView(
            frame: NSRect(x: 382, y: 8, width: 92, height: 40)
        )
        header.addSubview(dial)
        header.addSubview(dragRegion)

        XCTAssertFalse(dial.isInsideWindowDragRegion)
        XCTAssertTrue(dragRegion.isInsideWindowDragRegion)
    }

    func testStickyWindowReservesEveryNativeResizeEdgeBeforeHeaderDragging() {
        let window = StickyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let near = StickyWindow.nativeResizeEdgeInset - 1
        let beyond = StickyWindow.nativeResizeEdgeInset + 1

        for point in [
            NSPoint(x: near, y: near),
            NSPoint(x: 560 - near, y: near),
            NSPoint(x: near, y: 320 - near),
            NSPoint(x: 560 - near, y: 320 - near),
            NSPoint(x: 280, y: near),
            NSPoint(x: 280, y: 320 - near),
            NSPoint(x: near, y: 160),
            NSPoint(x: 560 - near, y: 160)
        ] {
            XCTAssertTrue(
                window.isInsideNativeResizeRegion(point),
                "AppKit must own resizing at \(point)"
            )
        }

        XCTAssertFalse(
            window.isInsideNativeResizeRegion(
                NSPoint(x: beyond, y: 320 - beyond)
            )
        )
        XCTAssertFalse(
            window.isInsideNativeResizeRegion(NSPoint(x: 280, y: 280))
        )
    }

    func testTickerAlwaysUsesDenseFacesAtEveryHeaderWidth() {
        XCTAssertEqual(DateTickerLayout.density, .numbersOnly)
    }

    func testV2CurvatureUsesTwentyDegreeFacesAndThreeHundredPointPerspective() {
        XCTAssertEqual(DateTickerLayout.anglePerDay, 20)
        XCTAssertEqual(DateTickerLayout.perspective, 300)
        XCTAssertEqual(
            DateTickerLayout.radius(for: .fullFaces),
            260.87,
            accuracy: 0.02
        )
    }

    func testRecessedDrumKeepsACompactHousingAndTrueFacePerspective() {
        XCTAssertEqual(DateTickerLayout.bandHeight, 40)
        XCTAssertEqual(DateTickerLayout.apertureHeight, 36)
        XCTAssertEqual(DateTickerLayout.apertureCornerRadius, 7)
        XCTAssertLessThan(
            DateTickerLayout.apertureHeight,
            DateTickerLayout.bandHeight
        )
        XCTAssertEqual(DateTickerLayout.facePerspective, 0.32)

        let center = DateTickerLayout.projection(
            forDayOffset: 0,
            visualRotation: 0,
            tickerWidth: DateTickerLayout.fixedWidth,
            density: .numbersOnly
        )
        let outer = DateTickerLayout.projection(
            forDayOffset: 2,
            visualRotation: 0,
            tickerWidth: DateTickerLayout.fixedWidth,
            density: .numbersOnly
        )

        XCTAssertLessThan(outer.scaleY, center.scaleY)
        XCTAssertLessThan(outer.opacity, center.opacity)
    }

    func testDenseModeExpandsOnlyTheSelectedFace() {
        XCTAssertFalse(
            DateTickerLayout.usesFullLabel(
                density: .numbersOnly,
                isSelected: false
            )
        )
        XCTAssertTrue(
            DateTickerLayout.usesFullLabel(
                density: .numbersOnly,
                isSelected: true
            )
        )
        XCTAssertEqual(
            DateTickerLayout.faceWidth(
                density: .numbersOnly,
                isSelected: false
            ),
            46
        )
        XCTAssertEqual(
            DateTickerLayout.faceWidth(
                density: .numbersOnly,
                isSelected: true
            ),
            92
        )
        XCTAssertEqual(
            DateTickerLayout.faceWidth(
                density: .fullFaces,
                isSelected: false
            ),
            92
        )
    }

    func testDialKeepsItsCompactWidthAndLeavesWideHeaderSpaceDraggable() {
        let controls = DateHeaderLayout.controlClusterWidth(
            isCompact: false,
            hasSearchReturn: true
        )

        XCTAssertEqual(controls, 164)
        XCTAssertEqual(DateHeaderLayout.tickerWidth, DateTickerLayout.fixedWidth)
        XCTAssertGreaterThan(
            DateHeaderLayout.windowDragGapWidth(
                headerWidth: 900,
                controlClusterWidth: controls
            ),
            DateHeaderLayout.controlSpacing
        )
    }

    func testCompactHeaderReservesEnoughWidthForDialAndAllControls() {
        let controls = DateHeaderLayout.controlClusterWidth(
            isCompact: true,
            hasSearchReturn: true
        )

        XCTAssertEqual(controls, 114)
        XCTAssertEqual(DateHeaderLayout.tickerWidth, 184)
        XCTAssertEqual(
            DateHeaderLayout.windowDragGapWidth(
                headerWidth: 320,
                controlClusterWidth: controls
            ),
            DateHeaderLayout.controlSpacing
        )
    }

    func testDialDragAndWindowDragRegionsRemainDisjointAtEveryHeaderWidth() {
        for headerWidth in [CGFloat(320), 400, 560, 900] {
            for hasSearchReturn in [false, true] {
                let controls = DateHeaderLayout.controlClusterWidth(
                    isCompact: headerWidth <= DateTickerLayout.compactHeaderWidth,
                    hasSearchReturn: hasSearchReturn
                )
                let ticker = DateHeaderLayout.tickerWidth
                let dragGap = DateHeaderLayout.windowDragGapWidth(
                    headerWidth: headerWidth,
                    controlClusterWidth: controls
                )

                XCTAssertGreaterThanOrEqual(dragGap, 0)
                XCTAssertEqual(
                    2 * DateHeaderLayout.horizontalPadding
                        + ticker
                        + dragGap
                        + controls,
                    headerWidth,
                    accuracy: 0.001
                )
            }
        }
    }

    func testProjectionCentersTheSelectedFaceAndCurvesAdjacentFaces() {
        let center = DateTickerLayout.projection(
            forDayOffset: 0,
            visualRotation: 0,
            tickerWidth: 320,
            density: .numbersOnly
        )
        let next = DateTickerLayout.projection(
            forDayOffset: 1,
            visualRotation: 0,
            tickerWidth: 320,
            density: .numbersOnly
        )

        XCTAssertEqual(center.x, 0, accuracy: 0.001)
        XCTAssertEqual(center.scaleX, 1, accuracy: 0.001)
        XCTAssertEqual(center.opacity, 1, accuracy: 0.001)
        XCTAssertGreaterThan(next.x, 40)
        XCTAssertLessThan(next.x, DateTickerLayout.compactFacePitch)
        XCTAssertLessThan(next.scaleX, 1)
        XCTAssertLessThan(next.opacity, 1)
    }

    func testSettledDialShowsOnlyTwoReadableFacesOnEachSide() {
        let projectionReferenceWidth: CGFloat = 374

        for density in [DateTickerDensity.fullFaces, .numbersOnly] {
            let offsets = DateTickerLayout.visibleDayOffsets(
                tickerWidth: projectionReferenceWidth,
                density: density,
                visualRotation: 0
            )

            XCTAssertEqual(offsets, [-2, -1, 0, 1, 2])
        }
    }

    func testNextRimFaceEntersContinuouslyDuringRotation() {
        let offsets = DateTickerLayout.visibleDayOffsets(
            tickerWidth: 374,
            density: .fullFaces,
            visualRotation: 10
        )

        XCTAssertTrue(offsets.contains(3))
        XCTAssertFalse(offsets.contains(-3))
    }

    func testDragSnapsInTheExpectedDirectionAndCapsFlicks() {
        XCTAssertEqual(
            DateTickerLayout.navigationDelta(translation: -43, predictedTranslation: -43),
            1
        )
        XCTAssertEqual(
            DateTickerLayout.navigationDelta(translation: 45, predictedTranslation: 45),
            -1
        )
        XCTAssertEqual(
            DateTickerLayout.navigationDelta(translation: -10, predictedTranslation: -500),
            5
        )
        XCTAssertEqual(
            DateTickerLayout.navigationDelta(translation: 10, predictedTranslation: 500),
            -5
        )
        XCTAssertEqual(
            DateTickerLayout.navigationDelta(translation: -440, predictedTranslation: -440),
            10
        )
        XCTAssertEqual(
            DateTickerLayout.navigationDelta(translation: -440, predictedTranslation: -1_000),
            15
        )
        XCTAssertEqual(
            DateTickerLayout.navigationDelta(translation: -220, predictedTranslation: -88),
            2
        )
    }

    func testFastFlickLandsBeforeCommittingItsDate() {
        let plan = DateTickerLayout.flickPlan(
            baseRotation: 0,
            translation: -10,
            predictedTranslation: -500
        )

        XCTAssertEqual(plan.days, 5)
        XCTAssertEqual(plan.startRotation, CGFloat(50) / 11, accuracy: 0.001)
        XCTAssertEqual(plan.targetRotation, 100, accuracy: 0.001)

        let firstFrame = DateTickerLayout.springStep(
            rotation: plan.startRotation,
            targetRotation: plan.targetRotation
        )
        XCTAssertGreaterThan(firstFrame, plan.startRotation)
        XCTAssertLessThan(firstFrame, plan.targetRotation)

        let beforeCommit = DateTickerLayout.projection(
            forDayOffset: plan.days,
            visualRotation: plan.targetRotation,
            tickerWidth: 184,
            density: .numbersOnly
        )
        let afterCommit = DateTickerLayout.projection(
            forDayOffset: 0,
            visualRotation: 0,
            tickerWidth: 184,
            density: .numbersOnly
        )

        XCTAssertEqual(beforeCommit.x, afterCommit.x, accuracy: 0.001)
        XCTAssertEqual(beforeCommit.scaleX, afterCommit.scaleX, accuracy: 0.001)
    }

    func testClickMapsToTheNearestTickerFace() {
        XCTAssertEqual(
            DateTickerLayout.clickedDayOffset(x: 246, width: 400, density: .numbersOnly),
            1
        )
        XCTAssertEqual(
            DateTickerLayout.clickedDayOffset(x: 108, width: 400, density: .fullFaces),
            -1
        )
    }

    func testEveryRenderedTickerFaceCenterSelectsItsOwnDate() {
        for density in [DateTickerDensity.fullFaces, .numbersOnly] {
            for width in [CGFloat(160), 260, 374] {
                let offsets = DateTickerLayout.visibleDayOffsets(
                    tickerWidth: width,
                    density: density,
                    visualRotation: 0
                )

                for offset in offsets {
                    let face = DateTickerLayout.projection(
                        forDayOffset: offset,
                        visualRotation: 0,
                        tickerWidth: width,
                        density: density
                    )
                    XCTAssertEqual(
                        DateTickerLayout.clickedDayOffset(
                            x: width / 2 + face.x,
                            width: width,
                            density: density
                        ),
                        offset,
                        "Failed offset \(offset), density \(density), width \(width)"
                    )
                }
            }
        }
    }

    func testExpandedDenseSelectionDoesNotStealAdjacentDateClicks() {
        let width: CGFloat = 260
        let density = DateTickerDensity.numbersOnly

        for offset in [-1, 1] {
            let face = DateTickerLayout.projection(
                forDayOffset: offset,
                visualRotation: 0,
                tickerWidth: width,
                density: density
            )
            XCTAssertEqual(
                DateTickerLayout.clickedDayOffset(
                    x: width / 2 + face.x,
                    width: width,
                    density: density
                ),
                offset
            )
        }
    }

    func testHiddenBackSideFacesCannotStealClicksAtTheDialEdges() {
        let width: CGFloat = 260
        let density = DateTickerDensity.numbersOnly
        let visibleOffsets = DateTickerLayout.visibleDayOffsets(
            tickerWidth: width,
            density: density,
            visualRotation: 0
        )

        XCTAssertEqual(
            DateTickerLayout.clickedDayOffset(
                x: 0,
                width: width,
                density: density
            ),
            visibleOffsets.min()
        )
        XCTAssertEqual(
            DateTickerLayout.clickedDayOffset(
                x: width,
                width: width,
                density: density
            ),
            visibleOffsets.max()
        )
    }

    func testNavigationPreservesTheRenderedFaceBeforeSpringingToRest() {
        XCTAssertEqual(
            DateTickerLayout.preservedRotation(visualRotation: 0, navigatingBy: 1),
            -20
        )
        XCTAssertEqual(
            DateTickerLayout.preservedRotation(visualRotation: 20, navigatingBy: 1),
            0
        )
    }

    func testClickNavigationRotatesAtAConstantAngularSpeed() {
        XCTAssertEqual(
            DateTickerLayout.clickTargetRotation(navigatingBy: 1),
            20
        )
        XCTAssertEqual(
            DateTickerLayout.clickTargetRotation(navigatingBy: -3),
            -60
        )
        XCTAssertEqual(
            DateTickerLayout.clickAnimationDuration(navigatingBy: 1),
            0.14,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DateTickerLayout.clickAnimationDuration(navigatingBy: 3),
            0.42,
            accuracy: 0.001
        )

        let oneDaySpeed = abs(
            DateTickerLayout.clickTargetRotation(navigatingBy: 1)
        ) / DateTickerLayout.clickAnimationDuration(navigatingBy: 1)
        let threeDaySpeed = abs(
            DateTickerLayout.clickTargetRotation(navigatingBy: 3)
        ) / DateTickerLayout.clickAnimationDuration(navigatingBy: 3)
        XCTAssertEqual(oneDaySpeed, threeDaySpeed, accuracy: 0.001)
    }

    func testTodayEdgeClicksUseFixedDurationWhileDateFacesKeepPerDayTiming() {
        let width: CGFloat = 184

        XCTAssertEqual(
            DateTickerLayout.clickPlan(
                x: 0,
                width: width,
                density: .numbersOnly,
                visualRotation: 0,
                todayEdge: .leading,
                currentDayOffsetFromToday: 2
            ),
            DateTickerClickPlan(days: -2, duration: 0.28)
        )
        XCTAssertEqual(
            DateTickerLayout.clickPlan(
                x: width,
                width: width,
                density: .numbersOnly,
                visualRotation: 0,
                todayEdge: .trailing,
                currentDayOffsetFromToday: -3
            ),
            DateTickerClickPlan(days: 3, duration: 0.28)
        )

        let nextFace = DateTickerLayout.projection(
            forDayOffset: 1,
            visualRotation: 0,
            tickerWidth: width,
            density: .numbersOnly
        )
        XCTAssertEqual(
            DateTickerLayout.clickPlan(
                x: width / 2 + nextFace.x,
                width: width,
                density: .numbersOnly,
                visualRotation: 0,
                todayEdge: .none,
                currentDayOffsetFromToday: 0
            ),
            DateTickerClickPlan(days: 1, duration: 0.14)
        )
    }

    func testTodayReturnSpeedScalesWithDistanceToKeepDurationConsistent() {
        let width: CGFloat = 184
        let nearPlan = DateTickerLayout.clickPlan(
            x: 0,
            width: width,
            density: .numbersOnly,
            visualRotation: 0,
            todayEdge: .leading,
            currentDayOffsetFromToday: 2
        )
        let farPlan = DateTickerLayout.clickPlan(
            x: 0,
            width: width,
            density: .numbersOnly,
            visualRotation: 0,
            todayEdge: .leading,
            currentDayOffsetFromToday: 20
        )

        XCTAssertEqual(nearPlan.duration, farPlan.duration, accuracy: 0.001)

        let nearSpeed = abs(
            DateTickerLayout.clickTargetRotation(navigatingBy: nearPlan.days)
        ) / nearPlan.duration
        let farSpeed = abs(
            DateTickerLayout.clickTargetRotation(navigatingBy: farPlan.days)
        ) / farPlan.duration
        XCTAssertEqual(farSpeed, nearSpeed * 10, accuracy: 0.001)
    }

    func testHeaderIconControlsOnlyShowTheirBackgroundDuringInteraction() {
        XCTAssertEqual(
            TickerHeaderControlAppearance.backgroundOpacity(
                isHovered: false,
                isPressed: false
            ),
            0
        )
        XCTAssertEqual(
            TickerHeaderControlAppearance.backgroundOpacity(
                isHovered: true,
                isPressed: false
            ),
            1
        )
        XCTAssertEqual(
            TickerHeaderControlAppearance.backgroundOpacity(
                isHovered: false,
                isPressed: true
            ),
            1
        )
    }

    func testTodayReturnFaceRotatesContinuouslyFromTheRimToCenter() {
        let width: CGFloat = 184
        let todayOffset = -2
        let rotations: [CGFloat] = [0, -20, -40]
        let projections = rotations.map { rotation in
            DateTickerLayout.projection(
                forDayOffset: todayOffset,
                visualRotation: rotation,
                tickerWidth: width,
                density: .numbersOnly
            )
        }

        XCTAssertLessThan(projections[0].x, projections[1].x)
        XCTAssertLessThan(projections[1].x, projections[2].x)
        XCTAssertLessThan(projections[0].scaleY, projections[1].scaleY)
        XCTAssertLessThan(projections[1].scaleY, projections[2].scaleY)
        XCTAssertEqual(projections[2].x, 0, accuracy: 0.001)
        XCTAssertEqual(projections[2].angle, 0, accuracy: 0.001)
    }

    func testTickerFaceIdentityFollowsItsDateAcrossNavigationCommit() {
        let targetBeforeCommit = DateTickerFacePlacement(
            id: "2026-08-26",
            offset: 1
        )
        let targetAfterCommit = DateTickerFacePlacement(
            id: "2026-08-26",
            offset: 0
        )

        XCTAssertEqual(targetBeforeCommit.id, targetAfterCommit.id)
        XCTAssertNotEqual(targetBeforeCommit.offset, targetAfterCommit.offset)

        let beforeProjection = DateTickerLayout.projection(
            forDayOffset: targetBeforeCommit.offset,
            visualRotation: DateTickerLayout.clickTargetRotation(navigatingBy: 1),
            tickerWidth: 184,
            density: .numbersOnly
        )
        let afterProjection = DateTickerLayout.projection(
            forDayOffset: targetAfterCommit.offset,
            visualRotation: 0,
            tickerWidth: 184,
            density: .numbersOnly
        )
        XCTAssertEqual(beforeProjection.x, afterProjection.x, accuracy: 0.001)
        XCTAssertEqual(beforeProjection.scaleX, afterProjection.scaleX, accuracy: 0.001)
    }

    func testTodayStaysOnTheRimUntilReachingTheHandoffAngle() {
        XCTAssertEqual(
            DateTickerLayout.todayEdge(
                tickerWidth: 300,
                currentDayOffsetFromToday: 1,
                visualRotation: 0,
                density: .fullFaces
            ),
            .none
        )
        XCTAssertEqual(
            DateTickerLayout.todayEdge(
                tickerWidth: 180,
                currentDayOffsetFromToday: 3,
                visualRotation: 0,
                density: .numbersOnly
            ),
            .leading
        )
        XCTAssertEqual(
            DateTickerLayout.todayEdge(
                tickerWidth: 180,
                currentDayOffsetFromToday: -3,
                visualRotation: 0,
                density: .numbersOnly
            ),
            .trailing
        )
    }

    func testTodayReturnTabFadesTheCompleteOuterFaceWithoutChoppingIt() {
        let width: CGFloat = 374
        let tabCenter = DateTickerLayout.todayTabWidth / 2
        let fullyVisibleCenter = DateTickerLayout.todayTabWidth
            + DateTickerLayout.fullFacePitch / 2

        XCTAssertEqual(
            DateTickerLayout.edgeFaceAttenuation(
                projectedX: tabCenter - width / 2,
                tickerWidth: width,
                density: .fullFaces,
                todayEdge: .leading
            ),
            0.14,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DateTickerLayout.edgeFaceAttenuation(
                projectedX: width / 2 - tabCenter,
                tickerWidth: width,
                density: .fullFaces,
                todayEdge: .trailing
            ),
            0.14,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DateTickerLayout.edgeFaceAttenuation(
                projectedX: fullyVisibleCenter - width / 2,
                tickerWidth: width,
                density: .fullFaces,
                todayEdge: .leading
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DateTickerLayout.edgeFaceAttenuation(
                projectedX: tabCenter - width / 2,
                tickerWidth: width,
                density: .fullFaces,
                todayEdge: .none
            ),
            1,
            accuracy: 0.001
        )
    }


    func testTodayHandsOffAtTheProjectedClipAngleDuringDrag() {
        let handoff = DateTickerLayout.handoffAngle(
            tickerWidth: 180,
            density: .numbersOnly
        )

        XCTAssertGreaterThanOrEqual(handoff, 16)
        XCTAssertLessThanOrEqual(handoff, 45)
        XCTAssertEqual(
            DateTickerLayout.todayEdge(
                tickerWidth: 180,
                currentDayOffsetFromToday: 0,
                visualRotation: handoff,
                density: .numbersOnly
            ),
            .leading
        )
    }

    func testTickerDatePartsAreLocalizedAndDayOffsetsCrossMonthBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let english = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        let chinese = DateKeyService(
            calendar: calendar,
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(
            english.tickerFaceContent(for: "2026-08-25"),
            DateTickerFaceContent(
                weekday: "TUE",
                day: "25",
                month: "AUG",
                accessibilityTitle: "Tuesday, August 25, 2026"
            )
        )
        XCTAssertEqual(english.dayOffset(from: "2026-08-31", to: "2026-09-02"), 2)
        XCTAssertTrue(chinese.tickerFaceContent(for: "2026-08-25")?.month.contains("8") == true)
    }
}
