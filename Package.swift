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
            checksum: "2a39465af3d9e77eed750b494272c690251824198f6d5b68cfa2d60f4bbc9b02a600976380d24f7911b396872fc83e8d6e748d71f176fbdb8075141447e67020"
        ),
        .testTarget(
            name: "PilotTests",
            dependencies: ["Pilot"],
            path: "Tests/PilotTests"
        ),
    ]
)
