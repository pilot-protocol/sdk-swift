// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pilot — Swift wrapper around the embedded pilot-daemon C ABI.
//
// Usage:
//
//   let p = try Pilot.start(.init(
//       dataDir: dir, socketPath: "p.sock",
//       trustAutoApprove: true, keepaliveSeconds: 2))
//   try p.handshake(peerID: 12345, justification: "hi")
//   _ = try p.waitForTrust(peerID: 12345, timeoutMs: 30_000)
//   try p.send(to: "0:0000.0000.AAAA", port: 7777, data: Data("hi".utf8))
//   let dg = try p.receive()
//   try p.stop()
//
// One Pilot instance owns one embedded daemon; the C ABI is
// process-global, so create a single Pilot at app launch.
//
// Unix socket sun_path is 104 bytes on darwin/ios. Pass a SHORT
// socketPath — relative paths land inside `dataDir` once Pilot.start
// chdir's there. iOS Application Support paths often exceed the
// limit, so use a basename like "p.sock".

import Foundation
import PilotC

public final class Pilot {

    // MARK: - Public types

    public struct Config {
        public var dataDir: URL
        public var socketPath: String          // relative basename recommended
        public var registryAddr: String        = "34.71.57.205:9000"
        public var beaconAddr: String          = "34.71.57.205:9001"
        public var trustAutoApprove: Bool      = false
        public var keepaliveSeconds: Int       = 30
        public var version: String             = "pilot-swift"

        public init(
            dataDir: URL,
            socketPath: String,
            trustAutoApprove: Bool = false,
            keepaliveSeconds: Int = 30
        ) {
            self.dataDir          = dataDir
            self.socketPath       = socketPath
            self.trustAutoApprove = trustAutoApprove
            self.keepaliveSeconds = keepaliveSeconds
        }
    }

    public struct StartResult {
        public let address: String
        public let nodeID: UInt32
        public let publicKey: String
    }

    public struct Datagram {
        public let srcAddr: String
        public let srcPort: UInt16
        public let dstPort: UInt16
        public let data: Data
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case startFailed(String)
        case rpcFailed(String)
        case invalidResponse(String)
        case dataTooLarge(Int)

        public var description: String {
            switch self {
            case .startFailed(let m):     return "Pilot start failed: \(m)"
            case .rpcFailed(let m):       return "Pilot RPC failed: \(m)"
            case .invalidResponse(let m): return "Pilot invalid response: \(m)"
            case .dataTooLarge(let n):    return "Pilot send: data \(n) bytes exceeds Int32.max (C ABI limit)"
            }
        }
    }

    // MARK: - Instance

    public let start: StartResult
    private let driverHandle: UInt64

    // PILOT-118: NSLock-guard the stopped flag so concurrent stop()/deinit
    // can't race. Stored as _stopped + a computed `stopped` property that
    // takes/releases the lock per access. Cheaper than a serial queue
    // since access is rare (stop path + deinit).
    private let stoppedLock = NSLock()
    private var _stopped = false
    private var stopped: Bool {
        get { stoppedLock.lock(); defer { stoppedLock.unlock() }; return _stopped }
        set { stoppedLock.lock(); defer { stoppedLock.unlock() }; _stopped = newValue }
    }

    /// True when this instance booted the process-global embedded daemon and
    /// is therefore responsible for stopping it in `stop()`.
    private let ownsEmbeddedDaemon: Bool

    private init(start: StartResult, driverHandle: UInt64, ownsEmbeddedDaemon: Bool = true) {
        self.start = start
        self.driverHandle = driverHandle
        self.ownsEmbeddedDaemon = ownsEmbeddedDaemon
    }

    /// Wrap an already-open driver connection (from `PilotConnect`) without
    /// booting the embedded daemon. `stop()` closes only the driver handle;
    /// the caller keeps ownership of whatever is serving the socket.
    internal static func attach(driverHandle: UInt64, start: StartResult) -> Pilot {
        Pilot(start: start, driverHandle: driverHandle, ownsEmbeddedDaemon: false)
    }

    deinit { if !stopped { try? stop() } }

    // MARK: - Lifecycle

    public static func start(_ config: Config) throws -> Pilot {
        try FileManager.default.createDirectory(
            at: config.dataDir, withIntermediateDirectories: true)

        if !config.socketPath.hasPrefix("/") {
            FileManager.default.changeCurrentDirectoryPath(config.dataDir.path)
        }

        let cfgDict: [String: Any] = [
            "data_dir":           config.dataDir.path,
            "socket_path":        config.socketPath,
            "registry_addr":      config.registryAddr,
            "beacon_addr":        config.beaconAddr,
            "trust_auto_approve": config.trustAutoApprove,
            "keepalive_sec":      config.keepaliveSeconds,
            "version":            config.version,
        ]
        let cfgData = try JSONSerialization.data(withJSONObject: cfgDict)
        let cfgStr  = String(data: cfgData, encoding: .utf8) ?? "{}"

        let startResp: [String: Any] = try cfgStr.withCString { cstr in
            try parseJSON(PilotEmbeddedStart(UnsafeMutablePointer(mutating: cstr)))
        }
        if let err = startResp["error"] as? String {
            throw Error.startFailed(err)
        }
        guard
            let address  = startResp["address"]    as? String,
            let nodeID   = (startResp["node_id"]   as? NSNumber)?.uint32Value,
            let pubkey   = startResp["public_key"] as? String
        else {
            throw Error.invalidResponse("start: \(startResp)")
        }
        let result = StartResult(address: address, nodeID: nodeID, publicKey: pubkey)

        let connRet = config.socketPath.withCString { sp in
            PilotConnect(UnsafeMutablePointer(mutating: sp))
        }
        if let errPtr = connRet.r1 {
            let s = String(cString: errPtr)
            FreeString(errPtr)
            throw Error.startFailed("driver connect: \(s)")
        }
        return Pilot(start: result, driverHandle: connRet.r0)
    }

    public func stop() throws {
        guard !stopped else { return }
        stopped = true
        _ = PilotClose(driverHandle)
        guard ownsEmbeddedDaemon else { return }
        let resp = try parseJSON(PilotEmbeddedStop())
        if let err = resp["error"] as? String { throw Error.rpcFailed(err) }
    }

    // MARK: - RPC

    public func info() throws -> [String: Any] {
        try rpc(PilotInfo(driverHandle))
    }

    public func health() throws -> [String: Any] {
        try rpc(PilotHealth(driverHandle))
    }

    public func handshake(peerID: UInt32, justification: String) throws {
        let _ = try justification.withCString { c in
            try rpc(PilotHandshake(driverHandle, peerID, UnsafeMutablePointer(mutating: c)))
        }
    }

    @discardableResult
    public func waitForTrust(peerID: UInt32, timeoutMs: UInt32) throws -> Bool {
        let resp = try rpc(PilotWaitForTrust(driverHandle, peerID, timeoutMs))
        return (resp["trusted"] as? Bool) ?? false
    }

    public func send(to peerAddr: String, port: UInt16, data: Data) throws {
        guard !data.isEmpty else { return }
        // PILOT-121: the C ABI PilotSendTo takes Int32 for length; if data.count
        // exceeds Int32.max (~2.14 GB) the truncation is silent and the wire
        // length is wrong. Guard explicitly with a typed error instead.
        guard data.count <= Int(Int32.max) else { throw Error.dataTooLarge(data.count) }
        let fullAddr = "\(peerAddr):\(port)"
        try fullAddr.withCString { addrC in
            try data.withUnsafeBytes { raw in
                let base = UnsafeMutableRawPointer(mutating: raw.baseAddress)
                let ret = PilotSendTo(
                    driverHandle,
                    UnsafeMutablePointer(mutating: addrC),
                    base,
                    Int32(data.count))
                // SendTo returns nil on success, errJSON on failure.
                if let p = ret {
                    let s = String(cString: p)
                    FreeString(p)
                    let obj = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
                    throw Error.rpcFailed(obj?["error"] as? String ?? s)
                }
            }
        }
    }

    public func receive() throws -> Datagram {
        try Pilot.decodeDatagram(try rpc(PilotRecvFrom(driverHandle)))
    }

    /// Build a `Datagram` from a decoded RecvFrom response body.
    /// Split out of `receive()` so the decode contract can be driven
    /// with response shapes the wire format cannot produce.
    internal static func decodeDatagram(_ resp: [String: Any]) throws -> Datagram {
        guard
            let src      = resp["src_addr"] as? String,
            let sportNum = resp["src_port"] as? NSNumber,
            let dportNum = resp["dst_port"] as? NSNumber,
            let sport    = port(from: sportNum),
            let dport    = port(from: dportNum)
        else {
            throw Error.invalidResponse("recv: \(resp)")
        }
        // Go's encoding/json renders []byte as base64.
        let data: Data
        if let b64 = resp["data"] as? String, let d = Data(base64Encoded: b64) {
            data = d
        } else if let raw = resp["data"] as? [UInt8] {
            data = Data(raw)
        } else {
            data = Data()
        }
        return Datagram(srcAddr: src, srcPort: sport, dstPort: dport, data: data)
    }

    /// Narrow an `NSNumber` to `UInt16` only when the value is exactly
    /// representable in 16 bits. `NSNumber.uint16Value` wraps silently —
    /// 70000 reads back as 4464 and -1 as 65535 — so compare in a single
    /// wide signed type first and reject anything out of range.
    private static func port(from n: NSNumber) -> UInt16? {
        let wide = n.int64Value
        guard wide >= 0, wide <= Int64(UInt16.max) else { return nil }
        return UInt16(wide)
    }

    public func trustedPeers() throws -> [[String: Any]] {
        let resp = try rpc(PilotTrustedPeers(driverHandle))
        return (resp["trusted"] as? [[String: Any]]) ?? []
    }

    // MARK: - Internal helpers

    private func rpc(_ result: UnsafeMutablePointer<CChar>?) throws -> [String: Any] {
        let resp = try parseJSON(result)
        if let err = resp["error"] as? String { throw Error.rpcFailed(err) }
        return resp
    }
}

/// Decode a freshly-allocated JSON-encoded char* from cgo, free it,
/// and return a [String: Any] dict. Throws Pilot.Error on failures.
fileprivate func parseJSON(_ p: UnsafeMutablePointer<CChar>?) throws -> [String: Any] {
    guard let p = p else {
        throw Pilot.Error.invalidResponse("null C return")
    }
    let s = String(cString: p)
    FreeString(p)
    let raw = try JSONSerialization.jsonObject(with: Data(s.utf8))
    guard let dict = raw as? [String: Any] else {
        throw Pilot.Error.invalidResponse("not a JSON object: \(s.prefix(200))")
    }
    return dict
}
