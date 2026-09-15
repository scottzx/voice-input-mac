import XCTest
@testable import VoiceInputCore

final class RightOptionGestureTests: XCTestCase {
    func testDoubleTapTogglesSticky() {
        var g = RightOptionGesture(longPress: 0.28, doubleClick: 0.38)
        XCTAssertNotNil(g.keyDown(now: 1.00))
        XCTAssertNil(g.keyUp(now: 1.05))
        XCTAssertNotNil(g.keyDown(now: 1.20))
        XCTAssertEqual(g.keyUp(now: 1.25), .stickyToggle)
    }

    func testSingleTapDoesNothing() {
        var g = RightOptionGesture()
        _ = g.keyDown(now: 1.0)
        XCTAssertNil(g.keyUp(now: 1.05))
        _ = g.keyDown(now: 2.0)
        XCTAssertNil(g.keyUp(now: 2.05))
    }

    func testLongPressStartAndRelease() {
        var g = RightOptionGesture(longPress: 0.28, doubleClick: 0.38)
        XCTAssertEqual(g.keyDown(now: 1.00), 1.28)
        XCTAssertEqual(g.longPressFired(now: 1.28), .holdStart)
        XCTAssertEqual(g.keyUp(now: 2.00), .holdEnd)
    }

    func testReleaseBeforeLongPressIsTap() {
        var g = RightOptionGesture(longPress: 0.28, doubleClick: 0.38)
        _ = g.keyDown(now: 1.00)
        XCTAssertNil(g.longPressFired(now: 1.10))
        XCTAssertNil(g.keyUp(now: 1.12))
    }

    func testHoldCancelsPendingDoubleClick() {
        var g = RightOptionGesture(longPress: 0.28, doubleClick: 0.38)
        _ = g.keyDown(now: 1.00)
        _ = g.keyUp(now: 1.05)
        _ = g.keyDown(now: 1.20)
        XCTAssertEqual(g.longPressFired(now: 1.48), .holdStart)
        XCTAssertEqual(g.keyUp(now: 1.80), .holdEnd)
    }
}
