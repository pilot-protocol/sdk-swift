// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import Pilot

final class ConfigTests: XCTestCase {

    func testInitAppliesDefaults() {
        let dir = URL(fileURLWithPath: "/tmp/pilot-tests-config")
        let cfg = Pilot.Config(dataDir: dir, socketPath: "p.sock")

        XCTAssertEqual(cfg.dataDir, dir)
        XCTAssertEqual(cfg.socketPath, "p.sock")
        XCTAssertEqual(cfg.registryAddr, "34.71.57.205:9000")
        XCTAssertEqual(cfg.beaconAddr, "34.71.57.205:9001")
        XCTAssertFalse(cfg.trustAutoApprove)
        XCTAssertEqual(cfg.keepaliveSeconds, 30)
        XCTAssertEqual(cfg.version, "pilot-swift")
    }

    func testInitAcceptsCustomTrustAndKeepalive() {
        let dir = URL(fileURLWithPath: "/tmp/pilot-tests-config2")
        let cfg = Pilot.Config(
            dataDir: dir,
            socketPath: "p.sock",
            trustAutoApprove: true,
            keepaliveSeconds: 5)

        XCTAssertTrue(cfg.trustAutoApprove)
        XCTAssertEqual(cfg.keepaliveSeconds, 5)
    }

    func testFieldsAreMutableAfterInit() {
        // Config is a struct with var fields, so callers can tweak
        // registry/beacon/version without going through the init.
        var cfg = Pilot.Config(
            dataDir: URL(fileURLWithPath: "/tmp/pilot-tests-config3"),
            socketPath: "p.sock")
        cfg.registryAddr = "192.0.2.1:9000"
        cfg.beaconAddr   = "192.0.2.1:9001"
        cfg.version      = "pilot-swift-test"

        XCTAssertEqual(cfg.registryAddr, "192.0.2.1:9000")
        XCTAssertEqual(cfg.beaconAddr, "192.0.2.1:9001")
        XCTAssertEqual(cfg.version, "pilot-swift-test")
    }

    func testShortSocketPathIsAcceptable() {
        // sun_path is 104 bytes on darwin/ios — anything under that fits.
        // We don't enforce the limit in the wrapper, but a relative basename
        // is well within bounds.
        let cfg = Pilot.Config(
            dataDir: URL(fileURLWithPath: "/tmp/x"),
            socketPath: "p.sock")
        XCTAssertLessThan(cfg.socketPath.utf8.count, 104)
    }

    func testFileURLDataDir() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pilot-cfg-tests")
        let cfg = Pilot.Config(dataDir: url, socketPath: "s.sock")
        XCTAssertTrue(cfg.dataDir.isFileURL)
        XCTAssertEqual(cfg.dataDir.lastPathComponent, "pilot-cfg-tests")
    }
}
