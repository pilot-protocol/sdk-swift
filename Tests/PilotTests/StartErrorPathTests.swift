// SPDX-License-Identifier: AGPL-3.0-or-later
//
// StartErrorPathTests — drive `Pilot.start(_:)` down its error
// branches. Opt-in via PILOT_INTEGRATION=1 because each test
// triggers a 50+ second registry-retry backoff inside the embedded
// daemon's startup loop (10 attempts at exponential backoff
// capped at 8s). Skipped by default to keep `swift test` snappy.
//
// What's exercised here that the existing IntegrationTests don't:
//   * Both arms of `if !config.socketPath.hasPrefix("/")` —
//     relative AND absolute socket paths.
//   * Two consecutive start attempts hitting the
//     "embedded daemon already started" guard inside libpilot
//     (PilotEmbeddedStart is process-global).
//   * .startFailed message-propagation contract from
//     libpilot → Pilot.swift.

import XCTest
import PilotC
@testable import Pilot

final class StartErrorPathTests: XCTestCase {

    private func skipUnlessOptedIn() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["PILOT_INTEGRATION"] == "1" else {
            throw XCTSkip(
                "set PILOT_INTEGRATION=1 to run; each test waits ~50s for registry-retry backoff")
        }
    }

    /// Per-test dataDir under NSTemporaryDirectory.
    private func tempDataDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pilot-startfail-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Build a config pointed at a guaranteed-dead registry. Port 1
    /// is reserved (tcpmux) and nothing listens on loopback in normal
    /// CI / dev environments, so dial fails immediately.
    private func deadRegistryConfig(socketPath: String) -> Pilot.Config {
        var cfg = Pilot.Config(
            dataDir: tempDataDir(),
            socketPath: socketPath,
            trustAutoApprove: false,
            keepaliveSeconds: 1)
        cfg.registryAddr = "127.0.0.1:1"
        cfg.beaconAddr   = "127.0.0.1:1"
        cfg.version      = "pilot-swift-start-error-tests"
        return cfg
    }

    /// Best-effort tear-down: even on failure, make sure we leave the
    /// process-global embedded daemon stopped so the next test starts
    /// from a clean slate. PilotEmbeddedStop is safe to call on
    /// not-started.
    private func resetEmbedded() {
        // Re-import via Pilot's wrapper isn't possible (Stop is on the
        // instance); reach through PilotC directly. PilotEmbeddedStop is
        // declared in pilot.h and bound by the binary target.
        // (We can't call it without importing PilotC, so this file
        // imports it just for that.)
        _ = PilotEmbeddedStop()
    }

    override func tearDown() {
        resetEmbedded()
        super.tearDown()
    }

    func testStartFailsWithRelativeSocketPath() throws {
        try skipUnlessOptedIn()
        // Relative socket path → triggers the `chdir` branch in
        // Pilot.start. Registry is dead so we exit on .startFailed.
        let cfg = deadRegistryConfig(socketPath: "p.sock")

        XCTAssertThrowsError(try Pilot.start(cfg)) { err in
            guard let pe = err as? Pilot.Error else {
                XCTFail("wrong error type: \(err)")
                return
            }
            switch pe {
            case .startFailed, .invalidResponse:
                break // expected
            case .rpcFailed(let m):
                XCTFail("unexpected rpcFailed: \(m)")
            case .dataTooLarge(let n):
                XCTFail("unexpected dataTooLarge(\(n)) on the start path")
            }
        }
    }

    func testStartFailsWithAbsoluteSocketPath() throws {
        try skipUnlessOptedIn()
        // Absolute socket path → SKIPS the chdir branch in Pilot.start.
        // Same dead-registry outcome.
        let socket = "/tmp/pilot-abs-\(UUID().uuidString.prefix(6)).sock"
        let cfg = deadRegistryConfig(socketPath: socket)

        XCTAssertThrowsError(try Pilot.start(cfg)) { err in
            XCTAssertTrue(err is Pilot.Error, "wrong error type: \(err)")
        }

        // Best-effort socket cleanup if libpilot created one before failing.
        try? FileManager.default.removeItem(atPath: socket)
    }

    func testTwoConsecutiveStartsBothFailSafely() throws {
        try skipUnlessOptedIn()
        // Confirms we don't accidentally leak the embedded.node singleton
        // between attempts — second call should ALSO fail (not panic),
        // either with another startFailed or with the "already started"
        // guard tripped if the first attempt got further than expected.
        let cfg1 = deadRegistryConfig(socketPath: "p.sock")
        XCTAssertThrowsError(try Pilot.start(cfg1))

        // Tear down before retry, mirroring real-world recovery flow.
        resetEmbedded()

        let cfg2 = deadRegistryConfig(socketPath: "p.sock")
        XCTAssertThrowsError(try Pilot.start(cfg2))
    }

    func testStartFailedErrorDetailsArePropagated() throws {
        try skipUnlessOptedIn()
        // The .startFailed payload should contain something descriptive,
        // not be empty. This verifies the libpilot → Pilot.swift error
        // hand-off preserves the underlying message.
        let cfg = deadRegistryConfig(socketPath: "p.sock")

        do {
            _ = try Pilot.start(cfg)
            XCTFail("expected start to fail with dead registry")
        } catch let pe as Pilot.Error {
            switch pe {
            case .startFailed(let msg):
                XCTAssertFalse(msg.isEmpty, "empty startFailed message")
                // Description should mention startup failure.
                XCTAssertTrue(pe.description.contains("start failed"))
            case .invalidResponse(let msg):
                XCTAssertFalse(msg.isEmpty, "empty invalidResponse message")
            case .rpcFailed:
                XCTFail("unexpected rpcFailed before start completed")
            case .dataTooLarge(let n):
                XCTFail("unexpected dataTooLarge(\(n)) before start completed")
            }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}

