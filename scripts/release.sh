#!/bin/sh
set -eu

VERSION="${1:-0.0.8}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST="$ROOT/dist/$VERSION"

rm -rf "$DIST"
mkdir -p "$DIST"

build_target() {
  target="$1"
  artifact="$2"
  echo "==> Building $artifact ($target)"
  zig build -Doptimize=ReleaseSmall -Dtarget="$target"
  cp "$ROOT/zig-out/bin/regatta" "$DIST/$artifact"
}

build_target aarch64-macos "regatta-darwin-arm64"
build_target x86_64-macos "regatta-darwin-x64"
build_target aarch64-linux-musl "regatta-linux-arm64"
build_target x86_64-linux-musl "regatta-linux-x64"

(
  cd "$DIST"
  shasum -a 256 regatta-* > SHA256SUMS
)

echo "Release artifacts written to $DIST"
ls -lh "$DIST"
