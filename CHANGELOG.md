# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.12.5]

### Changed
- **Version-locked to the daemon.** The Swift SDK now tracks the
  `pilot-protocol/pilotprotocol` daemon version instead of an independent
  `0.x` line. This release rebases the SDK onto daemon `v1.12.5`: the
  `PilotC` xcframework is rebuilt from the `pilot-protocol/libpilot` cgo
  bindings pinned to `pilotprotocol v1.12.5`, and `Package.swift` points at
  the `v1.12.5` release asset. Consume it with:

      .package(url: "https://github.com/pilot-protocol/sdk-swift.git",
               from: "1.12.5")

  Note the `0.2.0 -> 1.12.5` major bump: SwiftPM treats it as a new major
  line, so `from: "0.2.0"` consumers must opt in to `1.x`.

### Added
- **Self-updating release automation.** `.github/workflows/release-watch.yml`
  polls the upstream daemon every 30 minutes; on a newer release it dispatches
  `.github/workflows/publish.yml`, which builds the xcframework on macOS,
  computes its SHA-256, rewrites `Package.swift`, and cuts the tag + GitHub
  Release with the binary attached — the same self-polling pattern the npm and
  PyPI SDKs use. No more manual, drifting binary releases.

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
