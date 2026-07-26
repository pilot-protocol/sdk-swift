// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import Pilot

final class DatagramTests: XCTestCase {

    func testFieldsAreAssigned() {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let dg = Pilot.Datagram(
            srcAddr: "0:0000.0000.AAAA",
            srcPort: 5000,
            dstPort: 7,
            data: payload)

        XCTAssertEqual(dg.srcAddr, "0:0000.0000.AAAA")
        XCTAssertEqual(dg.srcPort, 5000)
        XCTAssertEqual(dg.dstPort, 7)
        XCTAssertEqual(dg.data, payload)
    }

    func testEmptyData() {
        let dg = Pilot.Datagram(
            srcAddr: "0:0.0.0",
            srcPort: 0,
            dstPort: 0,
            data: Data())
        XCTAssertEqual(dg.data.count, 0)
    }

    func testMaxPort() {
        let dg = Pilot.Datagram(
            srcAddr: "0:0.0.0",
            srcPort: UInt16.max,
            dstPort: UInt16.max,
            data: Data())
        XCTAssertEqual(dg.srcPort, UInt16.max)
        XCTAssertEqual(dg.dstPort, UInt16.max)
    }

    // The receive() path decodes `data` two ways: base64 string (what Go's
    // encoding/json emits for []byte), or a raw [UInt8] array. We can't run
    // receive() without a live daemon, but we exercise the same Foundation
    // decoder the wrapper relies on so a Foundation regression would surface
    // here too.

    func testBase64DecodeRoundtripMatchesWrapperPath() {
        let payload = Data("hello pilot".utf8)
        let b64 = payload.base64EncodedString()
        let decoded = Data(base64Encoded: b64)
        XCTAssertEqual(decoded, payload)
    }

    func testBase64DecodeRejectsGarbage() {
        // Wrapper falls back to raw bytes or empty Data if base64 decode
        // fails; this asserts the failure mode it depends on.
        XCTAssertNil(Data(base64Encoded: "!!!not base64!!!"))
    }

    func testBase64EmptyStringDecodesToEmptyData() {
        let d = Data(base64Encoded: "")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.count, 0)
    }

    func testRawByteArrayInitMatchesWrapperPath() {
        let raw: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        let d = Data(raw)
        XCTAssertEqual(d.count, 4)
        XCTAssertEqual(d, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    // MARK: - Port range validation (PILOT-119)

    /// Response body in the shape `receive()` hands to the decoder.
    private func recvBody(srcPort: Any, dstPort: Any) -> [String: Any] {
        [
            "src_addr": "0:0000.0000.AAAA",
            "src_port": srcPort,
            "dst_port": dstPort,
            "data":     Data("payload".utf8).base64EncodedString(),
        ]
    }

    func testPortTruncationDetection() throws {
        // NSNumber.uint16Value wraps: 70000 reads back as 4464, and -1 as
        // 65535. Both must be rejected rather than silently narrowed.
        XCTAssertEqual(NSNumber(value: 70000).uint16Value, 4464)
        XCTAssertEqual(NSNumber(value: -1).uint16Value, UInt16.max)

        for badPort in [70000, 65536, 4_294_967_295, -1] {
            let body = recvBody(srcPort: NSNumber(value: badPort), dstPort: 7)
            XCTAssertThrowsError(try Pilot.decodeDatagram(body),
                                 "src_port \(badPort) should be rejected") { err in
                guard case Pilot.Error.invalidResponse = err else {
                    return XCTFail("wrong case for \(badPort): \(err)")
                }
            }

            let body2 = recvBody(srcPort: 7, dstPort: NSNumber(value: badPort))
            XCTAssertThrowsError(try Pilot.decodeDatagram(body2),
                                 "dst_port \(badPort) should be rejected") { err in
                guard case Pilot.Error.invalidResponse = err else {
                    return XCTFail("wrong case for \(badPort): \(err)")
                }
            }
        }

        // Both ends of the valid range survive the round-trip intact.
        for goodPort in [0, 1, 7, 65535] {
            let dg = try Pilot.decodeDatagram(
                recvBody(srcPort: NSNumber(value: goodPort), dstPort: NSNumber(value: goodPort)))
            XCTAssertEqual(dg.srcPort, UInt16(goodPort))
            XCTAssertEqual(dg.dstPort, UInt16(goodPort))
            XCTAssertEqual(dg.srcAddr, "0:0000.0000.AAAA")
            XCTAssertEqual(dg.data, Data("payload".utf8))
        }
    }

    func testDecodeRejectsMissingAndMistypedFields() {
        let cases: [[String: Any]] = [
            ["src_port": 1, "dst_port": 2],                                 // no src_addr
            ["src_addr": "0:0.0.0", "dst_port": 2],                         // no src_port
            ["src_addr": "0:0.0.0", "src_port": 1],                         // no dst_port
            ["src_addr": 42, "src_port": 1, "dst_port": 2],                 // src_addr not a string
            ["src_addr": "0:0.0.0", "src_port": "1", "dst_port": 2],        // src_port not a number
        ]
        for body in cases {
            XCTAssertThrowsError(try Pilot.decodeDatagram(body), "should reject \(body)")
        }
    }

    func testDecodeFallsBackToRawByteArrayAndEmptyData() throws {
        var body = recvBody(srcPort: 1, dstPort: 2)
        body["data"] = [UInt8]([0xDE, 0xAD])
        XCTAssertEqual(try Pilot.decodeDatagram(body).data, Data([0xDE, 0xAD]))

        body["data"] = NSNull()
        XCTAssertEqual(try Pilot.decodeDatagram(body).data, Data())

        body.removeValue(forKey: "data")
        XCTAssertEqual(try Pilot.decodeDatagram(body).data, Data())
    }
}
