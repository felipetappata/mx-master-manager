import XCTest
@testable import MXMasterManager

final class MouseProtocolTests: XCTestCase {
    func testDPICompactRangeAndExplicitUpperEndpoint() throws {
        // Sensor 0: 200, range(step 50), 4000, terminator.
        let values = try MouseProtocol.dpiValues([0, 0, 200, 0xe0, 50, 0x0f, 0xa0, 0, 0])
        XCTAssertEqual(values, Array(stride(from: 200, through: 4000, by: 50)))
        let offGrid = try MouseProtocol.dpiValues([0, 0x01, 0x90, 0xe1, 0x90, 0x05, 0xdc, 0, 0])
        XCTAssertEqual(offGrid, [400, 800, 1200, 1500])
    }

    func testMalformedOrWrongSensorDPIRangesAreRejected() {
        for bytes: [UInt8] in [
            [1, 0x03, 0x20, 0, 0],
            [0, 0xe0, 50, 0x0f, 0xa0],
            [0, 0, 200, 0xe0, 0, 0x0f, 0xa0],
            [0, 0, 200, 0xe0, 50],
            [0, 0x03, 0x20, 0xe0, 50, 0, 200],
            [0, 0, 0],
        ] {
            XCTAssertThrowsError(try MouseProtocol.dpiValues(bytes), "\(bytes)")
        }
    }

    func testGestureDiversionTouchesOnlyOwnedFlags() {
        let gesture = MouseProtocol.reportingChange(cid: 0xc3, diverted: true, rawXY: true)
        XCTAssertEqual(Array(gesture.prefix(6)), [0, 0xc3, 0x33, 0, 0, 0])
        let back = MouseProtocol.reportingChange(cid: 0x53, diverted: true, rawXY: nil)
        XCTAssertEqual(Array(back.prefix(6)), [0, 0x53, 3, 0, 0, 0])
        let restored = MouseProtocol.reportingChange(cid: 0xc3, diverted: false, rawXY: false)
        XCTAssertEqual(Array(restored.prefix(6)), [0, 0xc3, 0x22, 0, 0, 0])
        // No remap, persistent-diversion, force-raw-XY or analytics mutation.
        XCTAssertTrue(gesture.dropFirst(3).allSatisfy { $0 == 0 })
    }

    func testReplyMatchesBothFeatureAndSoftwareID() throws {
        let message = try XCTUnwrap(HIDMessage(bytes: [0x10, 0xff, 8, 0x2b, 0, 0x08, 0x98]))
        XCTAssertEqual(try message.response(toFeature: 8, functionAndSoftware: 0x2b)?.get(), [0, 0x08, 0x98])
        XCTAssertNil(message.response(toFeature: 7, functionAndSoftware: 0x2b))
        XCTAssertNil(message.response(toFeature: 8, functionAndSoftware: 0x2a))
    }

    func testErrorPacketUsesShiftedHeader() throws {
        let error = try XCTUnwrap(HIDMessage(bytes: [0x10, 0xff, 0xff, 8, 0x2b, 2, 0]))
        guard case .failure(.protocolError(2))? = error.response(toFeature: 8, functionAndSoftware: 0x2b) else {
            return XCTFail("HID++ error must be matched to its rejected request")
        }
        XCTAssertNil(error.response(toFeature: 8, functionAndSoftware: 0x2a))
        XCTAssertNil(error.response(toFeature: 7, functionAndSoftware: 0x2b))
    }

    func testReportsRejectTruncationAndNonHIDPPIDs() {
        XCTAssertNil(HIDMessage(bytes: [0x11, 0xff, 1, 0]))
        XCTAssertNil(HIDMessage(bytes: [0x10, 0xff, 1, 0, 0, 0]))
        XCTAssertNil(HIDMessage(bytes: [0x12] + Array(repeating: 0, count: 63)))
    }

    func testSignedGestureDelta() {
        XCTAssertEqual(Int16(bitPattern: MouseProtocol.word([0xff, 0x9c])), -100)
        XCTAssertEqual(Int16(bitPattern: MouseProtocol.word([0, 100])), 100)
    }
}
