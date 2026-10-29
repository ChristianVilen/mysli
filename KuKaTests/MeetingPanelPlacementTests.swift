import XCTest
@testable import KuKa

final class MeetingPanelPlacementTests: XCTestCase {
    private let primary = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                         visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    private let right = ScreenGeometry(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                       visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))
    private let pill = CGSize(width: 232, height: 42)

    func testWithNoSavedCornerThePillSits16PointsInFromTheTopRightOfThePrimaryScreen() {
        let corner = MeetingPanelPlacement.pillTopRight(saved: nil, pillSize: pill, screens: [primary, right])

        XCTAssertEqual(corner, CGPoint(x: 1424, y: 859))
    }

    func testASavedCornerOnAScreenStaysWhereItIs() {
        let corner = MeetingPanelPlacement.pillTopRight(saved: CGPoint(x: 2000, y: 600), pillSize: pill,
                                                        screens: [primary, right])

        XCTAssertEqual(corner, CGPoint(x: 2000, y: 600))
    }

    func testASavedCornerPartlyOffScreenMovesSoTheWholePillIsOnThatScreen() {
        let corner = MeetingPanelPlacement.pillTopRight(saved: CGPoint(x: 3400, y: 1100), pillSize: pill,
                                                        screens: [primary, right])

        XCTAssertEqual(corner, CGPoint(x: 3360, y: 1055))
    }

    func testASavedCornerPastTheLeftEdgeMovesRightUntilThePillFits() {
        let corner = MeetingPanelPlacement.pillTopRight(saved: CGPoint(x: 100, y: 20), pillSize: pill,
                                                        screens: [primary])

        XCTAssertEqual(corner, CGPoint(x: 232, y: 42))
    }

    func testASavedCornerOnARemovedScreenFallsBackToTheDefault() {
        let corner = MeetingPanelPlacement.pillTopRight(saved: CGPoint(x: 3000, y: 500), pillSize: pill,
                                                        screens: [primary])

        XCTAssertEqual(corner, CGPoint(x: 1424, y: 859))
    }

    func testWithNoScreensThereIsNoCorner() {
        XCTAssertNil(MeetingPanelPlacement.pillTopRight(saved: nil, pillSize: pill, screens: []))
    }

    func testAClosedDrawerGivesThePillAlone() {
        let placed = MeetingPanelPlacement.frame(pillTopRight: CGPoint(x: 1424, y: 859), pillSize: pill,
                                                 drawerHeight: nil, screens: [primary])

        XCTAssertEqual(placed.frame, CGRect(x: 1192, y: 817, width: 232, height: 42))
        XCTAssertFalse(placed.drawerAbove)
    }

    func testTheDrawerOpensBelowThePill() {
        let placed = MeetingPanelPlacement.frame(pillTopRight: CGPoint(x: 1424, y: 859),
                                                 pillSize: CGSize(width: 380, height: 42),
                                                 drawerHeight: 280, screens: [primary])

        XCTAssertEqual(placed.frame, CGRect(x: 1044, y: 537, width: 380, height: 322))
        XCTAssertFalse(placed.drawerAbove)
    }

    func testTheDrawerOpensAboveThePillWhenItWouldNotFitBelow() {
        let placed = MeetingPanelPlacement.frame(pillTopRight: CGPoint(x: 1424, y: 300),
                                                 pillSize: CGSize(width: 380, height: 42),
                                                 drawerHeight: 280, screens: [primary])

        XCTAssertEqual(placed.frame, CGRect(x: 1044, y: 258, width: 380, height: 322))
        XCTAssertTrue(placed.drawerAbove)
    }

    func testTheDrawerOpensBelowWhenItFitsOnTheScreenThePillIsOn() {
        let lower = ScreenGeometry(frame: CGRect(x: 1440, y: -500, width: 1920, height: 1080),
                                   visibleFrame: CGRect(x: 1440, y: -500, width: 1920, height: 1055))

        let placed = MeetingPanelPlacement.frame(pillTopRight: CGPoint(x: 3000, y: 200),
                                                 pillSize: CGSize(width: 380, height: 42),
                                                 drawerHeight: 280, screens: [primary, lower])

        XCTAssertFalse(placed.drawerAbove)
        XCTAssertEqual(placed.frame.minY, -122)
    }

    func testTheDrawerHeightClampsTo140Through460() {
        XCTAssertEqual(MeetingPanelPlacement.clampedDrawerHeight(100), 140)
        XCTAssertEqual(MeetingPanelPlacement.clampedDrawerHeight(300), 300)
        XCTAssertEqual(MeetingPanelPlacement.clampedDrawerHeight(900), 460)
    }
}

final class TranscriptFollowTests: XCTestCase {
    func testItFollowsAtFirstAndOffersNoReturnToLive() {
        let follow = TranscriptFollow()

        XCTAssertTrue(follow.isFollowing)
        XCTAssertNil(follow.returnToLiveTitle)
    }

    func testFollowingStopsWhenTheLastRowLeavesViewAndStartsAgainWhenItIsBack() {
        var follow = TranscriptFollow()

        follow.scrolled(lastRowVisible: false)
        XCTAssertFalse(follow.isFollowing)
        XCTAssertEqual(follow.returnToLiveTitle, "Return to live")

        follow.scrolled(lastRowVisible: true)
        XCTAssertTrue(follow.isFollowing)
        XCTAssertNil(follow.returnToLiveTitle)
    }

    func testRowsAddedWhileNotFollowingAreCounted() {
        var follow = TranscriptFollow()
        follow.scrolled(lastRowVisible: false)

        follow.rowsChanged(from: 5, to: 7)
        follow.rowsChanged(from: 7, to: 8)

        XCTAssertEqual(follow.unseenRows, 3)
        XCTAssertEqual(follow.returnToLiveTitle, "Return to live · 3 new")
    }

    func testRowsAddedWhileFollowingAndRowsRemovedAreNotCounted() {
        var follow = TranscriptFollow()
        follow.rowsChanged(from: 5, to: 7)
        follow.scrolled(lastRowVisible: false)

        follow.rowsChanged(from: 7, to: 6)

        XCTAssertEqual(follow.unseenRows, 0)
    }

    func testReturnToLiveResetsTheCount() {
        var follow = TranscriptFollow()
        follow.scrolled(lastRowVisible: false)
        follow.rowsChanged(from: 1, to: 4)

        follow.returnToLive()

        XCTAssertTrue(follow.isFollowing)
        XCTAssertEqual(follow.unseenRows, 0)
        XCTAssertNil(follow.returnToLiveTitle)
    }

    func testScrollingBackToTheLastRowAlsoClearsTheCount() {
        var follow = TranscriptFollow()
        follow.scrolled(lastRowVisible: false)
        follow.rowsChanged(from: 1, to: 4)

        follow.scrolled(lastRowVisible: true)
        follow.scrolled(lastRowVisible: false)

        XCTAssertEqual(follow.returnToLiveTitle, "Return to live")
    }
}
