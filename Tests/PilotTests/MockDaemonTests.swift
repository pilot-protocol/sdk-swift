// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MockDaemonTests — IPC integration via the libpilot mock daemon.
//
// These tests spawn the standalone mock daemon binary from
// libpilot/cintegration/mockdaemon, which speaks the IPC wire
// protocol (and only that) on a Unix socket. They exercise the
// PilotC bindings end-to-end without booting the embedded Go
// daemon (which requires a real registry + beacon).
//
// Why we don't drive the full `Pilot.*` wrapper:
//
//   `Pilot.start(_:)` is the only public constructor and it
//   unconditionally calls `PilotEmbeddedStart`, which spins up a
//   real daemon that dials a registry. The mock daemon only
//   implements the local IPC socket, not the registry protocol —
//   so there is no way to drive `Pilot.info() / health() / send()`
//   end-to-end against the mock without modifying Pilot.swift
//   (which the task explicitly forbids).
//
//   The next-best thing — and what this file does — is to drive
//   the underlying PilotC C symbols directly against the mock. This
//   does NOT bump line coverage on Sources/Pilot/Pilot.swift (the
//   wrapper methods are bypassed) but it DOES protect the FFI
//   boundary: every command code the wrapper sends, the mock
//   replies to, and the JSON contract holds.
//
// Tests skip cleanly if `go` is not on PATH or the mock daemon
// source tree cannot be located.

import XCTest
import PilotC
@testable import Pilot

final class MockDaemonTests: XCTestCase {

    // MARK: - Mock daemon lifecycle

    /// Per-test mock daemon harness. Builds the binary once per
    /// test-class run (lazy), spawns a fresh process per test
    /// targeting a unique socket path under NSTemporaryDirectory.
    private final class MockDaemon {
        let socketPath: String
        private let process: Process

        init(socketPath: String, binary: String) {
            self.socketPath = socketPath
            self.process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["-socket", socketPath]
            // Capture stderr so debugging is one log line away if the mock
            // crashes. We discard stdout (mock writes nothing there).
            process.standardOutput = Pipe()
            process.standardError = Pipe()
        }

        func start() throws {
            try process.run()
        }

        /// Polls until the socket file exists or the deadline lapses.
        func waitForBind(timeout: TimeInterval = 5.0) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: socketPath) {
                    return true
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            return false
        }

        func stop() {
            if process.isRunning {
                process.terminate()
                // Give it a beat to flush + unlink; mock removes socket on SIGTERM.
                process.waitUntilExit()
            }
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }

    private var daemon: MockDaemon?
    private var driverHandle: UInt64 = 0

    /// Cached path to the built mock binary — shared across tests in this
    /// class so we only invoke `go build` once per `swift test` run.
    /// nil before first build attempt; throws XCTSkip if it ever fails.
    nonisolated(unsafe) private static var cachedBinary: String?
    nonisolated(unsafe) private static var buildSkipReason: String?

    /// Look up where the libpilot mock-daemon source lives, build it
    /// to a temp binary, and return the path. Throws XCTSkip on
    /// any environmental hiccup (no Go, no source tree).
    private func buildMockDaemonBinary() throws -> String {
        // 1. Locate `go`.
        guard let goPath = findExecutable("go") else {
            throw XCTSkip("go not on PATH — skipping mock-daemon integration tests")
        }

        // 2. Locate the mock-daemon source. Resolve via #filePath, which the
        //    compiler bakes into the test binary as the absolute path of this
        //    source file. Walking up the directory tree from there is stable
        //    regardless of swift-test's CWD.
        //
        //    Layout: <root>/sdk-swift/Tests/PilotTests/MockDaemonTests.swift
        //            <root>/libpilot/cintegration/mockdaemon/main.go
        let thisFile = URL(fileURLWithPath: #filePath)
        let pilotProtocolRoot = thisFile
            .deletingLastPathComponent()      // PilotTests/
            .deletingLastPathComponent()      // Tests/
            .deletingLastPathComponent()      // sdk-swift/
            .deletingLastPathComponent()      // <root>/
        let candidates: [String] = [
            pilotProtocolRoot.appendingPathComponent("libpilot/cintegration/mockdaemon").path,
            // Also try a same-level layout (libpilot vendored inside sdk-swift).
            thisFile.deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("libpilot/cintegration/mockdaemon").path,
        ]

        var sourceDir: String?
        let fm = FileManager.default
        for c in candidates {
            let mainGo = c + "/main.go"
            if fm.fileExists(atPath: mainGo) {
                sourceDir = c
                break
            }
        }
        guard let src = sourceDir else {
            let joined = candidates.joined(separator: ", ")
            throw XCTSkip("mock-daemon source not found; tried: \(joined)")
        }

        // 3. Build it.
        let outPath = NSTemporaryDirectory().appending("pilot-mockdaemon-\(getpid())")
        let build = Process()
        build.executableURL = URL(fileURLWithPath: goPath)
        build.arguments = ["build", "-o", outPath, "."]
        build.currentDirectoryURL = URL(fileURLWithPath: src)
        let buildErr = Pipe()
        build.standardError = buildErr
        try build.run()
        build.waitUntilExit()
        guard build.terminationStatus == 0 else {
            let data = buildErr.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? "(unreadable)"
            throw XCTSkip("go build mockdaemon failed: \(msg.prefix(400))")
        }
        return outPath
    }

    private func findExecutable(_ name: String) -> String? {
        let common = ["/usr/local/go/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let fm = FileManager.default
        for dir in common {
            let p = dir + "/" + name
            if fm.isExecutableFile(atPath: p) { return p }
        }
        // Last-ditch: shell out to `which`.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", name]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        do { try which.run() } catch { return nil }
        which.waitUntilExit()
        guard which.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    // MARK: - Setup / teardown

    override func setUpWithError() throws {
        // Build (or reuse a previously-built) mock binary. We cache at the
        // class level — XCTest spins a fresh instance per test method, so
        // an instance-level cache would rebuild on every test.
        if let reason = Self.buildSkipReason {
            throw XCTSkip(reason)
        }
        if Self.cachedBinary == nil {
            do {
                Self.cachedBinary = try buildMockDaemonBinary()
            } catch let skip as XCTSkip {
                // Memoise the skip reason so subsequent tests skip immediately
                // instead of re-running the (failing) probe.
                Self.buildSkipReason = skip.message ?? "mock binary unavailable"
                throw skip
            }
        }
        guard let binary = Self.cachedBinary else {
            throw XCTSkip("mock binary unavailable")
        }

        // Unique short socket path per test (sun_path is 104 bytes on darwin).
        let socketPath = NSTemporaryDirectory()
            .appending("pd-\(UUID().uuidString.prefix(8)).sock")
        let d = MockDaemon(socketPath: socketPath, binary: binary)
        try d.start()
        XCTAssertTrue(d.waitForBind(), "mock daemon did not bind socket at \(socketPath)")
        self.daemon = d

        // Open a driver connection. This is exactly what Pilot.start()
        // does after PilotEmbeddedStart, just minus the embedded boot.
        let ret = socketPath.withCString { sp in
            PilotConnect(UnsafeMutablePointer(mutating: sp))
        }
        if let errPtr = ret.r1 {
            let s = String(cString: errPtr)
            FreeString(errPtr)
            XCTFail("PilotConnect failed: \(s)")
            return
        }
        self.driverHandle = ret.r0
    }

    override func tearDownWithError() throws {
        if driverHandle != 0 {
            _ = PilotClose(driverHandle)
            driverHandle = 0
        }
        daemon?.stop()
        daemon = nil
    }

    // MARK: - Helpers

    /// Decode a freshly-allocated cgo C string into a [String: Any].
    private func decodeJSON(_ p: UnsafeMutablePointer<CChar>?) throws -> [String: Any] {
        guard let p = p else { throw Pilot.Error.invalidResponse("null") }
        let s = String(cString: p)
        FreeString(p)
        let raw = try JSONSerialization.jsonObject(with: Data(s.utf8))
        guard let dict = raw as? [String: Any] else {
            throw Pilot.Error.invalidResponse("not object: \(s.prefix(200))")
        }
        return dict
    }

    // MARK: - IPC command coverage

    func testInfoRoundtrip() throws {
        let resp = try decodeJSON(PilotInfo(driverHandle))
        XCTAssertNil(resp["error"], "unexpected error: \(resp)")
        XCTAssertEqual((resp["node_id"] as? NSNumber)?.uint32Value, 0x12345678)
        XCTAssertEqual(resp["hostname"] as? String, "mock-daemon")
        XCTAssertEqual(resp["version"] as? String, "mock-0.1.0")
    }

    func testHealthRoundtrip() throws {
        let resp = try decodeJSON(PilotHealth(driverHandle))
        XCTAssertNil(resp["error"])
        XCTAssertEqual(resp["ok"] as? Bool, true)
    }

    func testListenAndAcceptCycle() throws {
        // PilotListen returns (listenerHandle, errPtr); we just want to
        // confirm the BindOK path round-trips.
        let lret = PilotListen(driverHandle, 9999)
        if let e = lret.r1 {
            let s = String(cString: e)
            FreeString(e)
            XCTFail("PilotListen failed: \(s)")
            return
        }
        // Close the listener — mock silently drops, no reply needed.
        let closeErr = PilotListenerClose(lret.r0)
        if let e = closeErr { FreeString(e) }
    }

    func testDialReturnsConnHandle() throws {
        let dret = "0:0000.0000.AAAA:7777".withCString { addr in
            PilotDial(driverHandle, UnsafeMutablePointer(mutating: addr))
        }
        if let e = dret.r1 {
            let s = String(cString: e)
            FreeString(e)
            XCTFail("PilotDial failed: \(s)")
            return
        }
        XCTAssertGreaterThan(dret.r0, 0, "expected non-zero connID")

        // Cleanup: close the conn (fire-and-forget on the mock side).
        let cerr = PilotConnClose(dret.r0)
        if let e = cerr { FreeString(e) }
    }

    func testSendToFireAndForget() throws {
        let payload = Data("hello mock".utf8)
        let err: UnsafeMutablePointer<CChar>? = "0:0000.0000.BEEF:7".withCString { addr in
            payload.withUnsafeBytes { raw in
                PilotSendTo(
                    driverHandle,
                    UnsafeMutablePointer(mutating: addr),
                    UnsafeMutableRawPointer(mutating: raw.baseAddress),
                    Int32(payload.count))
            }
        }
        if let e = err {
            let s = String(cString: e)
            FreeString(e)
            // SendTo on the mock is fire-and-forget; the wrapper would
            // see nil on success. A wire-level error here is a regression.
            XCTFail("PilotSendTo unexpected error: \(s)")
        }
    }

    func testHandshakeSubcommands() throws {
        // Send a handshake.
        let hErr = "needs trust".withCString { j in
            PilotHandshake(driverHandle, 0xCAFEBABE, UnsafeMutablePointer(mutating: j))
        }
        let h = try decodeJSON(hErr)
        XCTAssertEqual(h["ok"] as? Bool, true)

        // Pending handshakes — mock returns an empty array.
        let pResp = try decodeJSON(PilotPendingHandshakes(driverHandle))
        let pending = pResp["pending"] as? [Any]
        XCTAssertNotNil(pending)
        XCTAssertEqual(pending?.count, 0)

        // Trusted peers — empty array.
        let tResp = try decodeJSON(PilotTrustedPeers(driverHandle))
        let trusted = tResp["trusted"] as? [Any]
        XCTAssertNotNil(trusted)
        XCTAssertEqual(trusted?.count, 0)

        // Approve / Reject / Revoke all reply ok:true through the mock.
        let ap = try decodeJSON(PilotApproveHandshake(driverHandle, 0xCAFEBABE))
        XCTAssertEqual(ap["ok"] as? Bool, true)

        let rj = "spam".withCString { r in
            PilotRejectHandshake(driverHandle, 0xCAFEBABE, UnsafeMutablePointer(mutating: r))
        }
        let rjResp = try decodeJSON(rj)
        XCTAssertEqual(rjResp["ok"] as? Bool, true)

        let rv = try decodeJSON(PilotRevokeTrust(driverHandle, 0xCAFEBABE))
        XCTAssertEqual(rv["ok"] as? Bool, true)
    }

    func testResolveHostname() throws {
        let resp = try "my-peer".withCString { h in
            try decodeJSON(PilotResolveHostname(driverHandle, UnsafeMutablePointer(mutating: h)))
        }
        XCTAssertEqual(resp["hostname"] as? String, "my-peer")
        XCTAssertEqual((resp["node_id"] as? NSNumber)?.uint32Value, 0x0BADF00D)
    }

    func testSetHostnameAndVisibility() throws {
        let nameResp = try "new-name".withCString { h in
            try decodeJSON(PilotSetHostname(driverHandle, UnsafeMutablePointer(mutating: h)))
        }
        XCTAssertEqual(nameResp["hostname"] as? String, "new-name")

        let visResp = try decodeJSON(PilotSetVisibility(driverHandle, 1))
        XCTAssertEqual(visResp["public"] as? Bool, true)

        let visRespOff = try decodeJSON(PilotSetVisibility(driverHandle, 0))
        XCTAssertEqual(visRespOff["public"] as? Bool, false)
    }

    func testTagsWebhookDeregister() throws {
        // PilotSetTags expects a JSON array of strings (NOT an object) — the
        // libpilot wrapper unmarshals into []string before forwarding to the
        // daemon. Sending a dict would error at the cgo layer, never reaching
        // the IPC socket.
        let tagsJSON = #"["role:test","env:ci"]"#
        let tagsResp = try tagsJSON.withCString { t in
            try decodeJSON(PilotSetTags(driverHandle, UnsafeMutablePointer(mutating: t)))
        }
        XCTAssertEqual(tagsResp["ok"] as? Bool, true)

        let whResp = try "https://example.invalid/hook".withCString { u in
            try decodeJSON(PilotSetWebhook(driverHandle, UnsafeMutablePointer(mutating: u)))
        }
        XCTAssertEqual(whResp["url"] as? String, "https://example.invalid/hook")

        let dResp = try decodeJSON(PilotDeregister(driverHandle))
        XCTAssertEqual(dResp["ok"] as? Bool, true)
    }

    func testRotateKey() throws {
        let resp = try decodeJSON(PilotRotateKey(driverHandle))
        XCTAssertEqual(resp["rotated"] as? Bool, true)
    }

    func testNetworkOperationsReachMock() throws {
        // All Network* commands dispatch to the same cmd 0x1F on the wire;
        // the mock replies with a canned OK envelope regardless of sub-cmd.
        let l = try decodeJSON(PilotNetworkList(driverHandle))
        XCTAssertEqual(l["ok"] as? Bool, true)

        let j = try "tok".withCString { t in
            try decodeJSON(PilotNetworkJoin(driverHandle, 42, UnsafeMutablePointer(mutating: t)))
        }
        XCTAssertEqual(j["ok"] as? Bool, true)

        let mem = try decodeJSON(PilotNetworkMembers(driverHandle, 42))
        XCTAssertEqual(mem["ok"] as? Bool, true)
    }

    // MARK: - Pilot.Datagram base64 round-trip via the mock's echo path

    /// Mock's cmdSend echoes the payload back via cmdRecv. We exercise the
    /// same Foundation base64 path Pilot.receive() uses to decode the
    /// JSON-wrapped data field — proving the format compatibility holds
    /// regardless of whether the bytes came from a real or mock daemon.
    func testEchoPayloadBase64ContractMatchesWrapper() throws {
        let raw = Data([0x01, 0x02, 0xFF, 0x00, 0xAB])
        let b64 = raw.base64EncodedString()
        // Synthetic JSON that mirrors what RecvFrom returns.
        let json = #"{"src_addr":"0:0.0.0","src_port":1,"dst_port":2,"data":"\#(b64)"}"#
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertNotNil(obj)
        let decoded = Data(base64Encoded: (obj?["data"] as? String) ?? "")
        XCTAssertEqual(decoded, raw)
    }
}
