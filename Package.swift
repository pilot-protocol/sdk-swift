// swift-tools-version:5.9
// SPDX-License-Identifier: AGPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "Pilot",
    platforms: [
        .iOS(.v14),
        .macOS(.v12),
    ],
    products: [
        .library(name: "Pilot", targets: ["Pilot"]),
    ],
    targets: [
        .target(
            name: "Pilot",
            dependencies: ["PilotC"],
            path: "Sources/Pilot"
        ),
        .binaryTarget(
            name: "PilotC",
            url: "https://github.com/pilot-protocol/sdk-swift/releases/download/v0.2.0/Pilot.xcframework.zip",
            // SwiftPM binaryTarget checksums are SHA-256 (64 hex chars).
            // The previous value was 128 hex (a SHA-512), which SwiftPM
            // accepted at parse time but rejected at fetch:
            // "checksum of downloaded artifact … does not match …".
            // Recomputed via `swift package compute-checksum`.
            checksum: "a59c9b99061d1078cc6f5e7ae1261af90144e2177cdb1b932fbcf3979578a25e"
        ),
        .testTarget(
            name: "PilotTests",
            dependencies: ["Pilot"],
            path: "Tests/PilotTests"
        ),
    ]
)
