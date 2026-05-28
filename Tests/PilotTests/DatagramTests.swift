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
}

    // MARK: - Port truncation validation (PILOT-119)

    func testPortTruncationDetection() {
        // uint16Value truncates values > 65535 silently.
        // A value of 70000 truncates to 4464 (70000 - 65536).
        // The receive() path must reject such values.
        let n70000 = NSNumber(value: 70000)
        XCTAssertNotEqual(n70000.uint16Value, n70000.uint64Value,
                          "70000 should be detected as truncated")

        let n65535 = NSNumber(value: 65535)
        XCTAssertEqual(n65535.uint16Value, n65535.uint64Value,
                       "65535 is max valid port, should not truncate")

        let n0 = NSNumber(value: 0)
        XCTAssertEqual(n0.uint16Value, n0.uint64Value,
                       "port 0 is valid, should not truncate")

        let nNegative = NSNumber(value: -1)
        // intValue == -1, uint64Value would wrap around for negative
        XCTAssertNotEqual(Int64(nNegative.intValue), Int64(bitPattern: nNegative.uint64Value),
                          "negative values should be distinguishable from valid ports")
    }
