// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Opt-in tests that boot the embedded daemon. The daemon dials a registry
// and beacon over the public internet, so these are skipped unless
// PILOT_INTEGRATION=1 is set. Set PILOT_REGISTRY / PILOT_BEACON to point
// at your own test infra.

import XCTest
@testable import Pilot

final class IntegrationTests: XCTestCase {

    private func skipUnlessOptedIn() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["PILOT_INTEGRATION"] == "1" else {
            throw XCTSkip("set PILOT_INTEGRATION=1 to run daemon-backed tests")
        }
    }

    private func tempDataDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pilot-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testStartStopRoundtrip() throws {
        try skipUnlessOptedIn()

        var cfg = Pilot.Config(
            dataDir: tempDataDir(),
            socketPath: "p.sock",
            trustAutoApprove: true,
            keepaliveSeconds: 2)
        let env = ProcessInfo.processInfo.environment
        if let r = env["PILOT_REGISTRY"] { cfg.registryAddr = r }
        if let b = env["PILOT_BEACON"]   { cfg.beaconAddr   = b }

        let p = try Pilot.start(cfg)
        defer { try? p.stop() }

        XCTAssertFalse(p.start.address.isEmpty)
        XCTAssertNotEqual(p.start.nodeID, 0)
        XCTAssertFalse(p.start.publicKey.isEmpty)

        let info = try p.info()
        XCTAssertFalse(info.isEmpty)

        let health = try p.health()
        XCTAssertFalse(health.isEmpty)

        let trusted = try p.trustedPeers()
        XCTAssertNotNil(trusted)

        try p.stop()
    }

    func testStartFailsOnUnreachableRegistry() throws {
        try skipUnlessOptedIn()

        var cfg = Pilot.Config(
            dataDir: tempDataDir(),
            socketPath: "p.sock",
            keepaliveSeconds: 1)
        cfg.registryAddr = "127.0.0.1:1"   // nothing listens here
        cfg.beaconAddr   = "127.0.0.1:1"

        XCTAssertThrowsError(try Pilot.start(cfg)) { err in
            guard let pe = err as? Pilot.Error else {
                XCTFail("wrong error type: \(err)")
                return
            }
            switch pe {
            case .startFailed, .invalidResponse:
                break                                 // expected
            case .rpcFailed(let m):
                XCTFail("unexpected rpcFailed: \(m)")
            case .dataTooLarge(let n):
                XCTFail("unexpected dataTooLarge(\(n)) on the start path")
            }
        }
    }
}
