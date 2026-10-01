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
            url: "https://github.com/pilot-protocol/sdk-swift/releases/download/v1.14.0/Pilot.xcframework.zip",
            // SwiftPM binaryTarget checksums are SHA-256 (64 hex chars),
            // computed via `swift package compute-checksum Pilot.xcframework.zip`.
            // This and the url above are rewritten automatically by
            // .github/workflows/publish.yml on every daemon release so the
            // SDK stays version-locked to pilot-protocol/pilotprotocol.
            checksum: "a98cd8af1263254cdb9b887371ad98302ce90ce714d2c808fd8d6707654bfaa6"
        ),
        .testTarget(
            name: "PilotTests",
            dependencies: ["Pilot"],
            path: "Tests/PilotTests"
        ),
    ]
)
