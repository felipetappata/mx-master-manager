import AppKit
import CoreGraphics
import XCTest
@testable import MXMasterManager

final class NativeGestureTests: XCTestCase {
    func testBeganDecodesAsAppKitBegan() throws {
        try assertMagnification(phase: .began)
    }

    func testChangedWithNonzeroAmountDecodesAsAppKitChanged() throws {
        try assertMagnification(phase: .changed)
    }

    func testEndedDecodesAsAppKitEnded() throws {
        try assertMagnification(phase: .ended)
    }

    func testCancelledDecodesAsAppKitCancelled() throws {
        try assertMagnification(phase: .cancelled)
    }

    func testUnsupportedAppKitPhaseIsRejected() {
        XCTAssertNil(NativeGesture.make(.magnify(0.037, phase: .stationary), location: nil))
    }

    func testSmartZoomDecodesAsSmartMagnifyAtAnchor() throws {
        let anchor = CGPoint(x: 420, y: 260)
        let event = try XCTUnwrap(NativeGesture.make(.smartZoom, location: anchor))
        let native = try XCTUnwrap(NSEvent(cgEvent: event))
        XCTAssertEqual(native.type, .smartMagnify)
        XCTAssertEqual(event.location, anchor)
    }

    /// Construct and decode without posting any input to the user's session.
    /// Checking AppKit's decoded phase catches the different HID wire encoding.
    private func assertMagnification(phase: NSEvent.Phase,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let amount = 0.037
        let anchor = CGPoint(x: 420, y: 260)
        let event = try XCTUnwrap(NativeGesture.make(.magnify(amount, phase: phase), location: anchor), file: file, line: line)
        let native = try XCTUnwrap(NSEvent(cgEvent: event), file: file, line: line)
        XCTAssertEqual(native.type, .magnify, file: file, line: line)
        XCTAssertEqual(native.phase, phase, file: file, line: line)
        XCTAssertEqual(native.magnification, amount, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(event.location, anchor, file: file, line: line)
    }
}
