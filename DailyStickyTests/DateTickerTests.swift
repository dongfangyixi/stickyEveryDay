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

    func testDensitySwitchesAtFourHundredPointHeaderWidth() {
        XCTAssertEqual(DateTickerLayout.density(forHeaderWidth: 399), .numbersOnly)
        XCTAssertEqual(DateTickerLayout.density(forHeaderWidth: 400), .numbersOnly)
        XCTAssertEqual(DateTickerLayout.density(forHeaderWidth: 401), .fullFaces)
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

    func testDialUsesPrototypeMaximumWidthAndLeavesWideHeaderSpaceDraggable() {
        let controls = DateHeaderLayout.controlClusterWidth(
            isCompact: false,
            hasSearchReturn: true
        )

        XCTAssertEqual(controls, 164)
        XCTAssertEqual(
            DateHeaderLayout.tickerWidth(
                headerWidth: 560,
                controlClusterWidth: controls
            ),
            DateTickerLayout.maximumWidth
        )
        XCTAssertEqual(
            DateHeaderLayout.tickerWidth(
                headerWidth: 900,
                controlClusterWidth: controls
            ),
            DateTickerLayout.maximumWidth
        )
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
        XCTAssertEqual(
            DateHeaderLayout.tickerWidth(
                headerWidth: 320,
                controlClusterWidth: controls
            ),
            184
        )
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
                let ticker = DateHeaderLayout.tickerWidth(
                    headerWidth: headerWidth,
                    controlClusterWidth: controls
                )
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
