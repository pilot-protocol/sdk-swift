# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.2.0]

### Changed
- **Binary distribution via GitHub Releases.** The `PilotC` xcframework is
  no longer expected to live at a local `Frameworks/Pilot.xcframework`
  path — it's downloaded by SwiftPM from the GitHub Release asset and
  verified against a SHA-256 checksum baked into `Package.swift`. Consumers
  can now depend on `sdk-swift` purely by URL:

      .package(url: "https://github.com/pilot-protocol/sdk-swift.git",
               from: "0.2.0")

  with no local clone, no manual xcframework build step.

  Migration: nothing to do — your `Frameworks/Pilot.xcframework/` checkout
  (if you had one) is now ignored. To revert to a local binary for
  development (faster iteration when changing the cgo bindings), edit
  `Package.swift` and replace the binaryTarget with the previous
  `path: "Frameworks/Pilot.xcframework"` form locally.

## [v0.1.0]

Initial release.
