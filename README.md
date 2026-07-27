# Pilot Protocol — Swift SDK

[![ci](https://github.com/pilot-protocol/sdk-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/pilot-protocol/sdk-swift/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/pilot-protocol/sdk-swift/branch/main/graph/badge.svg)](https://codecov.io/gh/pilot-protocol/sdk-swift)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

End-to-end-encrypted peer-to-peer messaging for iOS and macOS apps, built on the [Pilot Protocol](https://pilotprotocol.network) overlay network.

The SDK ships an embedded `pilot-daemon` compiled to a static library inside an `XCFramework`. Your app links against it, calls a Swift API, and gets a real Pilot node — no separate process, no system-wide socket. Single-process, sandbox-clean.

## What you get

- Ed25519 identity, generated on first launch and persisted to `dataDir`
- Registration with the Pilot registry
- Mutual-trust handshake with arbitrary nodes
- Encrypted UDP tunnels (X25519 + AES-256-GCM), NAT-traversed via beacons
- Application-level `send` / `receive`
- The same wire protocol the macOS/Linux `pilot-daemon` speaks

## Install

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pilot-protocol/sdk-swift.git", from: "1.13.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Pilot", package: "sdk-swift"),
        ]
    ),
]
```

Or, in Xcode: **File → Add Package Dependencies…** and paste the repo URL.

Requires iOS 14+ or macOS 12+, Swift 5.9+.

## Quick start

```swift
import Foundation
import Pilot

let dataDir = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("pilot")

// Start the embedded daemon (no separate process needed).
let pilot = try Pilot.start(.init(
    dataDir: dataDir,
    socketPath: "p.sock",
    trustAutoApprove: true,
    keepaliveSeconds: 30
))

print("address=\(pilot.start.address) node_id=\(pilot.start.nodeID)")

// Confirm the node is up.
let health = try pilot.health()
print("status=\(health["status"] ?? "unknown")")

// To talk to a peer, handshake first, then send once trusted:
//
//   try pilot.handshake(peerID: 12345, justification: "hello")
//   _ = try pilot.waitForTrust(peerID: 12345, timeoutMs: 30_000)
//   try pilot.send(to: "0:0000.0000.AAAA", port: 7777, data: Data("hi".utf8))
//
// And drain inbound datagrams on a background task:
//
//   Task {
//       while let dg = try? pilot.receive() {
//           print("got \(dg.data.count) bytes from \(dg.srcAddr):\(dg.srcPort)")
//       }
//   }

// On shutdown
try pilot.stop()
```

The socket path must be short — Unix `sun_path` is 104 bytes on Darwin. Pass a basename; `Pilot.start` will `chdir(dataDir)` so the socket lives inside your sandbox.

## Building the XCFramework from source

The pre-built `Frameworks/Pilot.xcframework` is committed for convenience. To regenerate it:

```sh
scripts/build-xcframework.sh
```

This produces three slices via `go build -buildmode=c-archive` + `xcodebuild -create-xcframework`:

- `ios-arm64` — iOS device
- `ios-arm64-simulator` — iOS simulator on Apple Silicon
- `macos-arm64` — macOS arm64 (for `swift test` and host dev)

## Smoke testing

```sh
xcrun simctl boot "iPhone 17"

scripts/run-smoke-sim.sh info
scripts/run-smoke-sim.sh alice
scripts/run-smoke-sim.sh bob <peer_id> <peer_addr>
```

A full peer-to-peer orchestration recipe lives in `Examples/pilot-smoke-swift/`.

## Constraints

- **One Pilot per process.** The embedded daemon is process-global. Create a single `Pilot` at app launch and reuse it.
- **iOS background.** When iOS suspends the app, the embedded daemon pauses. Use `BGAppRefreshTask` or push-triggered wake for catch-up; always-on operation requires a `NEPacketTunnelProvider` extension.
- **Identity at rest.** v0 writes `identity.json` to the sandbox as plaintext. Secure Enclave wrapping is on the roadmap.
- **No `NetworkExtension` entitlement** is needed for outbound traffic.

## Links

- Homepage: <https://pilotprotocol.network>
- Issues: <https://github.com/pilot-protocol/sdk-swift/issues>
- Node.js SDK: [`pilotprotocol`](https://www.npmjs.com/package/pilotprotocol) on npm
- Python SDK: [`pilotprotocol`](https://pypi.org/project/pilotprotocol/) on PyPI

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).
