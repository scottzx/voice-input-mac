import XCTest
@testable import VoiceInputCore

final class RightOptionGestureTests: XCTestCase {
    func testDefaultsMatchMacOSDoubleClick() {
        let g = RightOptionGesture()
        XCTAssertEqual(g.longPress, 0.28, accuracy: 0.001)
        XCTAssertEqual(g.doubleClick, 0.50, accuracy: 0.001)
    }

    func testDoubleTapEmitsPolish() {
        var g = RightOptionGesture(longPress: 0.28, doubleClick: 0.38)
        XCTAssertNotNil(g.keyDown(now: 1.00))
        XCTAssertNil(g.keyUp(now: 1.05))
        XCTAssertNotNil(g.keyDown(now: 1.20))
        XCTAssertEqual(g.keyUp(now: 1.25), .doubleClickPolish)
    }

    func testSingleTapEmitsClickToggleAfterWindow() {
        var g = RightOptionGesture(longPress: 0.28, doubleClick: 0.38)
        _ = g.keyDown(now: 1.0)
        XCTAssertNil(g.keyUp(now: 1.05))
        XCTAssertEqual(g.clickWindowExpired(now: 1.43), .clickToggle)
    }

    func testClickWindowAfterStaleTapIsOneShot() {
        var g = RightOptionGesture(longPress: 0.28, doubleClick: 0.38)
        _ = g.keyDown(now: 1.0)
        XCTAssertNil(g.keyUp(now: 1.05))
        XCTAssertEqual(g.clickWindowExpired(now: 1.43), .clickToggle)
        XCTAssertNil(g.clickWindowExpired(now: 2.00))
    }

    func testClickWindowDeferredWhileKeyDown() {
        var g = RightOptionGesture(longPress: 0.28, doubleClick: 0.38)
        _ = g.keyDown(now: 1.0)
        XCTAssertNil(g.keyUp(now: 1.05))
        _ = g.keyDown(now: 1.10)
        XCTAssertNil(g.clickWindowExpired(now: 1.20))
        XCTAssertEqual(g.keyUp(now: 1.12), .doubleClickPolish)
    }

    func testSingleTapOutOfWindowDoesNothingImmediately() {
        var g = RightOptionGesture()
        _ = g.keyDown(now: 1.0)
        XCTAssertNil(g.keyUp(now: 1.05))
        _ = g.keyDown(now: 2.0)
        XCTAssertNil(g.keyUp(now: 2.05))
    }

    func testDefaultDoubleClickWindowAcceptsHalfSecond() {
        // Two taps 0.45s apart should still register as a double-click with the default threshold.
        var g = RightOptionGesture()
        _ = g.keyDown(now: 1.00)
        XCTAssertNil(g.keyUp(now: 1.05))
        _ = g.keyDown(now: 1.50)
        XCTAssertEqual(g.keyUp(now: 1.55), .doubleClickPolish)
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
        XCTAssertNil(g.clickWindowExpired(now: 2.00))
    }

    func testSingleTapImmediateEmitsClickToggleOnKeyUp() {
        var g = RightOptionGesture(longPress: 0.28, doubleClick: 0.38, singleTapImmediate: true)
        _ = g.keyDown(now: 1.00)
        XCTAssertEqual(g.keyUp(now: 1.05), .clickToggle)
    }
}