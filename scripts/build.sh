#!/bin/sh
# Build the StatusGlance release binary and copy it to a fixed path ($1).
#
# Tries the plain `swift build` first. If that fails, falls back through
# toolchain workarounds so the self-updater keeps working on a fresh macOS:
#
#   1. default build system, default SDK        (normal case)
#   2. native build system, default SDK
#   3. native build system, each older installed SDK, newest first
#
# Why: the macOS 27 Command Line Tools ship a `swiftbuild` backend that fails
# to initialize ("Unknown error parsing property list"), and a macOS 27 SDK
# whose SwiftUI `@State` needs the SwiftUIMacros compiler plugin — which only
# full Xcode includes. Building natively against the still-installed 26.x SDK
# works and produces a binary that runs fine on 27.
set -u

OUT="${1:?usage: build.sh <output-binary-path>}"
PRODUCT=StatusGlance

log() { echo "[build] $*"; }

try_build() { # $1 = label, rest = extra swift build args (SDKROOT via env)
    label="$1"; shift
    log "attempt: $label"
    if swift build -c release "$@" >/tmp/statusglance-build.$$ 2>&1; then
        bin_dir=$(swift build -c release "$@" --show-bin-path 2>/dev/null)
        if [ -x "$bin_dir/$PRODUCT" ]; then
            mkdir -p "$(dirname "$OUT")"
            cp "$bin_dir/$PRODUCT" "$OUT"
            log "ok: $label -> $OUT"
            rm -f /tmp/statusglance-build.$$
            return 0
        fi
    fi
    tail -3 /tmp/statusglance-build.$$ | cut -c1-200 | sed 's/^/[build]   /'
    rm -f /tmp/statusglance-build.$$
    return 1
}

try_build "default" && exit 0
try_build "native build system" --build-system native && exit 0

# Older SDKs installed alongside the default one (real dirs, not the
# MacOSX.sdk / MacOSXNN.sdk symlinks), newest first.
sdk_dir=$(dirname "$(xcrun --show-sdk-path 2>/dev/null)")
default_sdk=$(cd "$(xcrun --show-sdk-path 2>/dev/null)" 2>/dev/null && pwd -P)
for sdk in $(ls -d "$sdk_dir"/MacOSX[0-9]*.sdk 2>/dev/null | sort -V -r); do
    [ -L "$sdk" ] && continue
    [ "$(cd "$sdk" && pwd -P)" = "$default_sdk" ] && continue
    export SDKROOT="$sdk"
    try_build "native build system + $(basename "$sdk")" --build-system native && exit 0
    unset SDKROOT
done

log "all build attempts failed"
exit 1
