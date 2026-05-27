#!/usr/bin/env bash
# Build Pilot.xcframework from the libpilot Go bindings package.
#
# Produces three slices in $OUT, then bundles them via
# xcodebuild -create-xcframework:
#
#   ios-arm64                 — iOS device (iPhone/iPad arm64)
#   ios-arm64-simulator       — iOS simulator on Apple Silicon
#   macos-arm64               — macOS arm64 (for tests + local dev)
#
# Intel simulator (x86_64) is skipped; add an extra clang line if you
# need it. Re-run is idempotent: the script deletes $OUT/Pilot.xcframework
# before recreating it.
#
# Source location:
#   LIBPILOT_REPO env var (highest precedence) → must point at a
#     pilot-protocol/libpilot checkout containing go.mod + bindings.go.
#   ../libpilot relative to this clone (default — works when both
#     sdk-swift and libpilot are cloned as siblings under the
#     pilot-protocol org folder).
#
# Releases are normally pre-built and attached to the GitHub Release
# (Pilot.xcframework.zip on each tag); this script is for local dev
# when you're iterating on the cgo bindings and want a fresh slice.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_DIR="$(cd "$THIS_DIR/.." && pwd)"
OUT="$SWIFT_DIR/Frameworks"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Resolve LIBPILOT_REPO. Order of precedence:
#   1. $LIBPILOT_REPO env var
#   2. ../libpilot sibling to this clone
if [ -z "${LIBPILOT_REPO:-}" ]; then
    candidate="$SWIFT_DIR/../libpilot"
    if [ -d "$candidate" ] && [ -f "$candidate/go.mod" ]; then
        LIBPILOT_REPO="$candidate"
    fi
fi
if [ -z "${LIBPILOT_REPO:-}" ] || [ ! -f "$LIBPILOT_REPO/go.mod" ]; then
    cat >&2 <<EOF
ERROR: cannot find libpilot Go source.
Set LIBPILOT_REPO to point at a clone of pilot-protocol/libpilot.

    export LIBPILOT_REPO=/path/to/libpilot
    $0

Or clone libpilot as a sibling of sdk-swift:
    git clone git@github.com:pilot-protocol/libpilot.git $SWIFT_DIR/../libpilot
EOF
    exit 1
fi

echo ">>> using LIBPILOT_REPO=$LIBPILOT_REPO"
mkdir -p "$OUT"
rm -rf "$OUT/Pilot.xcframework"

build_slice() {
    local label="$1" sdk="$2" goarch="$3" minver_flag="$4"
    local out_dir="$WORK/$label"
    mkdir -p "$out_dir/Headers"

    local sdkpath cc
    sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
    cc="$(xcrun --sdk "$sdk" --find clang) -isysroot $sdkpath -arch $goarch $minver_flag"

    echo ">>> building $label ($sdk / $goarch)"
    CGO_ENABLED=1 GOOS=ios GOARCH=arm64 CC="$cc" \
        go build -C "$LIBPILOT_REPO" \
        -buildmode=c-archive \
        -tags ios \
        -ldflags="-s -w" \
        -o "$out_dir/libPilot.a" \
        .

    # The generated header sits next to the .a; rename to pilot.h and
    # write a module.modulemap so Swift can import it as "PilotC".
    mv "$out_dir/libPilot.h" "$out_dir/Headers/pilot.h"
    cat > "$out_dir/Headers/module.modulemap" <<'EOF'
module PilotC {
    header "pilot.h"
    link "Pilot"
    export *
}
EOF
}

# 1. iOS device (arm64)
build_slice "ios-arm64" \
    "iphoneos" "arm64" "-mios-version-min=14.0"

# 2. iOS simulator (Apple Silicon)
build_slice "ios-arm64-simulator" \
    "iphonesimulator" "arm64" "-mios-simulator-version-min=14.0"

# 3. macOS arm64 — useful for `swift test` and host-side experiments
#    Built via the macosx SDK; GOOS=darwin (the only slice where iOS
#    isn't the target).
echo ">>> building macos-arm64 (darwin)"
mkdir -p "$WORK/macos-arm64/Headers"
SDK_MAC="$(xcrun --sdk macosx --show-sdk-path)"
CC_MAC="$(xcrun --sdk macosx --find clang) -isysroot $SDK_MAC -arch arm64"
CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 CC="$CC_MAC" \
    go build -C "$LIBPILOT_REPO" \
    -buildmode=c-archive \
    -ldflags="-s -w" \
    -o "$WORK/macos-arm64/libPilot.a" \
    .
mv "$WORK/macos-arm64/libPilot.h" "$WORK/macos-arm64/Headers/pilot.h"
cat > "$WORK/macos-arm64/Headers/module.modulemap" <<'EOF'
module PilotC {
    header "pilot.h"
    link "Pilot"
    export *
}
EOF

# 4. Pack into Pilot.xcframework
echo ">>> creating Pilot.xcframework"
xcodebuild -create-xcframework \
    -library "$WORK/ios-arm64/libPilot.a" \
    -headers "$WORK/ios-arm64/Headers" \
    -library "$WORK/ios-arm64-simulator/libPilot.a" \
    -headers "$WORK/ios-arm64-simulator/Headers" \
    -library "$WORK/macos-arm64/libPilot.a" \
    -headers "$WORK/macos-arm64/Headers" \
    -output "$OUT/Pilot.xcframework"

echo
echo "✓ built $OUT/Pilot.xcframework"
du -sh "$OUT/Pilot.xcframework"/*/* 2>/dev/null | sort
