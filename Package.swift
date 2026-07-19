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
            url: "https://github.com/pilot-protocol/sdk-swift/releases/download/v1.13.1/Pilot.xcframework.zip",
            // SwiftPM binaryTarget checksums are SHA-256 (64 hex chars),
            // computed via `swift package compute-checksum Pilot.xcframework.zip`.
            // This and the url above are rewritten automatically by
            // .github/workflows/publish.yml on every daemon release so the
            // SDK stays version-locked to pilot-protocol/pilotprotocol.
            checksum: "93dc2ab270b5f3c2a36f885f0a799df67b19a5120c0484ee8582e7605e9f730b"
        ),
        .testTarget(
            name: "PilotTests",
            dependencies: ["Pilot"],
            path: "Tests/PilotTests"
        ),
    ]
)
