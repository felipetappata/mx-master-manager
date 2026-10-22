import XCTest
@testable import MXMasterCore

final class GestureStateTests: XCTestCase {
    func testTapWithSmallJitterProducesOnlySmartZoom() {
        var gesture = GestureState()
        gesture.press(at: 10)
        XCTAssertEqual(gesture.move(dx: 2, dy: -2), [])
        XCTAssertEqual(gesture.move(dx: -2, dy: 2), [])
        XCTAssertEqual(gesture.release(at: 10.2), [.smartZoom])
        XCTAssertEqual(gesture.release(at: 10.3), [])
    }

    func testForwardDragAndImmediateReverseProduceOppositeMagnification() {
        var gesture = GestureState()
        gesture.press(at: 0)
        XCTAssertEqual(gesture.move(dx: 0, dy: -20), [.beginZoom, .magnify(0.012)])
        XCTAssertEqual(gesture.move(dx: 0, dy: 10), [.magnify(-0.015)])
        XCTAssertEqual(gesture.release(at: 0.3), [.endZoom(cancelled: false)])
    }

    func testBackwardDragZoomsOutAndCannotBecomeTapAfterReturningToOrigin() {
        var gesture = GestureState()
        gesture.press(at: 0)
        XCTAssertEqual(gesture.move(dx: 0, dy: 20), [.beginZoom, .magnify(-0.012)])
        XCTAssertEqual(gesture.move(dx: 0, dy: -20), [.magnify(0.03)])
        XCTAssertEqual(gesture.release(at: 0.2), [.endZoom(cancelled: false)])
    }

    func testHorizontalDragSuppressesTapWithoutZoom() {
        var gesture = GestureState()
        gesture.press(at: 0)
        XCTAssertEqual(gesture.move(dx: 30, dy: 2), [])
        XCTAssertEqual(gesture.move(dx: -30, dy: -2), [])
        XCTAssertEqual(gesture.release(at: 0.2), [])
    }

    func testLongStationaryHoldDoesNotTriggerTap() {
        var gesture = GestureState()
        gesture.press(at: 0)
        XCTAssertEqual(gesture.release(at: 1), [])
    }

    func testCancelEndsGestureExactlyOnceAndNeverTaps() {
        var gesture = GestureState()
        gesture.press(at: 0)
        _ = gesture.move(dx: 0, dy: -20)
        XCTAssertEqual(gesture.cancel(), [.endZoom(cancelled: true)])
        XCTAssertEqual(gesture.cancel(), [])
        XCTAssertEqual(gesture.release(at: 0.2), [])
        gesture.press(at: 1)
        XCTAssertEqual(gesture.cancel(), [])
    }

    func testStrayMotionAndDuplicatePressDoNotChangeLifecycle() {
        var gesture = GestureState()
        XCTAssertEqual(gesture.move(dx: 0, dy: -100), [])
        gesture.press(at: 0)
        _ = gesture.move(dx: 0, dy: -20)
        gesture.press(at: 0.1)
        XCTAssertEqual(gesture.move(dx: 0, dy: 2), [.magnify(-0.003)])
        XCTAssertEqual(gesture.release(at: 0.2), [.endZoom(cancelled: false)])
    }

    func testDeadzoneSensitivityAndLargeReportBound() {
        var gesture = GestureState()
        gesture.press(at: 0)
        XCTAssertEqual(gesture.move(dx: 0, dy: -11), [])
        XCTAssertEqual(gesture.move(dx: 0, dy: -1), [.beginZoom])
        XCTAssertEqual(gesture.move(dx: 0, dy: -10, sensitivity: 2), [.magnify(0.03)])
        XCTAssertEqual(gesture.move(dx: 0, dy: Int.min), [.magnify(0.25)])
    }
}
