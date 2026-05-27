// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import Pilot

final class ErrorTests: XCTestCase {

    func testStartFailedDescription() {
        let e = Pilot.Error.startFailed("registry unreachable")
        XCTAssertEqual(e.description, "Pilot start failed: registry unreachable")
        XCTAssertEqual(String(describing: e), "Pilot start failed: registry unreachable")
    }

    func testRpcFailedDescription() {
        let e = Pilot.Error.rpcFailed("handshake denied")
        XCTAssertEqual(e.description, "Pilot RPC failed: handshake denied")
    }

    func testInvalidResponseDescription() {
        let e = Pilot.Error.invalidResponse("not a JSON object: ...")
        XCTAssertEqual(e.description, "Pilot invalid response: not a JSON object: ...")
    }

    func testEmptyMessageStillRenders() {
        XCTAssertEqual(Pilot.Error.startFailed("").description,     "Pilot start failed: ")
        XCTAssertEqual(Pilot.Error.rpcFailed("").description,       "Pilot RPC failed: ")
        XCTAssertEqual(Pilot.Error.invalidResponse("").description, "Pilot invalid response: ")
    }

    func testErrorsConformToSwiftError() {
        let errs: [Swift.Error] = [
            Pilot.Error.startFailed("a"),
            Pilot.Error.rpcFailed("b"),
            Pilot.Error.invalidResponse("c"),
        ]
        XCTAssertEqual(errs.count, 3)
        for err in errs {
            // localizedDescription always works on Swift errors; this just
            // proves the conformance compiles and the value can be thrown.
            XCTAssertFalse(err.localizedDescription.isEmpty)
        }
    }

    func testThrowAndCatchStartFailed() {
        func raise() throws { throw Pilot.Error.startFailed("boom") }

        XCTAssertThrowsError(try raise()) { err in
            guard case Pilot.Error.startFailed(let msg) = err else {
                XCTFail("wrong case: \(err)")
                return
            }
            XCTAssertEqual(msg, "boom")
        }
    }

    func testThrowAndCatchRpcFailed() {
        func raise() throws { throw Pilot.Error.rpcFailed("nope") }

        XCTAssertThrowsError(try raise()) { err in
            guard case Pilot.Error.rpcFailed(let msg) = err else {
                XCTFail("wrong case: \(err)")
                return
            }
            XCTAssertEqual(msg, "nope")
        }
    }

    func testThrowAndCatchInvalidResponse() {
        func raise() throws { throw Pilot.Error.invalidResponse("malformed") }

        XCTAssertThrowsError(try raise()) { err in
            guard case Pilot.Error.invalidResponse(let msg) = err else {
                XCTFail("wrong case: \(err)")
                return
            }
            XCTAssertEqual(msg, "malformed")
        }
    }

    func testDescriptionsAreDistinctPerCase() {
        let a = Pilot.Error.startFailed("x").description
        let b = Pilot.Error.rpcFailed("x").description
        let c = Pilot.Error.invalidResponse("x").description
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(b, c)
        XCTAssertNotEqual(a, c)
    }
}
