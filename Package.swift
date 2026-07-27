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
            url: "https://github.com/pilot-protocol/sdk-swift/releases/download/v1.13.7/Pilot.xcframework.zip",
            // SwiftPM binaryTarget checksums are SHA-256 (64 hex chars),
            // computed via `swift package compute-checksum Pilot.xcframework.zip`.
            // This and the url above are rewritten automatically by
            // .github/workflows/publish.yml on every daemon release so the
            // SDK stays version-locked to pilot-protocol/pilotprotocol.
            checksum: "2c853ab6ad143d5d1f62448b322847ce92075f84f72c11942c4d3766b217fdfd"
        ),
        .testTarget(
            name: "PilotTests",
            dependencies: ["Pilot"],
            path: "Tests/PilotTests"
        ),
    ]
)
