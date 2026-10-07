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
            url: "https://github.com/pilot-protocol/sdk-swift/releases/download/v1.17.0/Pilot.xcframework.zip",
            // SwiftPM binaryTarget checksums are SHA-256 (64 hex chars),
            // computed via `swift package compute-checksum Pilot.xcframework.zip`.
            // This and the url above are rewritten automatically by
            // .github/workflows/publish.yml on every daemon release so the
            // SDK stays version-locked to pilot-protocol/pilotprotocol.
            checksum: "3b8c3c30bf2c47f2762426ba2c1c4a27c776452248a3134663f381e2fe50fdc4"
        ),
        .testTarget(
            name: "PilotTests",
            dependencies: ["Pilot"],
            path: "Tests/PilotTests"
        ),
    ]
)
