// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import Pilot

final class StartResultTests: XCTestCase {

    func testFieldsAreAssigned() {
        let r = Pilot.StartResult(
            address: "0:0000.0000.AAAA",
            nodeID: 12345,
            publicKey: "abc123pubkey==")

        XCTAssertEqual(r.address, "0:0000.0000.AAAA")
        XCTAssertEqual(r.nodeID, 12345)
        XCTAssertEqual(r.publicKey, "abc123pubkey==")
    }

    func testZeroNodeIDIsAllowed() {
        let r = Pilot.StartResult(address: "0:0000.0000.0000", nodeID: 0, publicKey: "")
        XCTAssertEqual(r.nodeID, 0)
        XCTAssertEqual(r.publicKey, "")
    }

    func testMaxUInt32NodeID() {
        let r = Pilot.StartResult(address: "0:FFFF.FFFF.FFFF", nodeID: UInt32.max, publicKey: "k")
        XCTAssertEqual(r.nodeID, UInt32.max)
    }

    func testAddressFormatIsOpaque() {
        // StartResult does not parse / validate addresses. Whatever the
        // embedded daemon returns is stored verbatim.
        let r = Pilot.StartResult(address: "not-a-real-address", nodeID: 1, publicKey: "k")
        XCTAssertEqual(r.address, "not-a-real-address")
    }
}
