#!/usr/bin/env bash
# Build an XCFramework for iOS device + simulator and regenerate Swift bindings.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_DIR="$ROOT/rust"
OUT_DIR="$ROOT/ios/ResvgMobileFFI.xcframework"
GEN_DIR="$ROOT/ios/Sources/ResvgMobile/Generated"
TARGET_DIR="${CARGO_TARGET_DIR:-$RUST_DIR/target}"

cd "$RUST_DIR"

TARGETS=(
  aarch64-apple-ios
  aarch64-apple-ios-sim
  x86_64-apple-ios
)

for t in "${TARGETS[@]}"; do
  rustup target add "$t" >/dev/null
done

echo "==> Building staticlibs"
cargo build -p resvg-mobile --release --target aarch64-apple-ios
cargo build -p resvg-mobile --release --target aarch64-apple-ios-sim
cargo build -p resvg-mobile --release --target x86_64-apple-ios

IOS_LIB="$TARGET_DIR/aarch64-apple-ios/release/libuniffi_resvg_mobile.a"
SIM_ARM="$TARGET_DIR/aarch64-apple-ios-sim/release/libuniffi_resvg_mobile.a"
SIM_X64="$TARGET_DIR/x86_64-apple-ios/release/libuniffi_resvg_mobile.a"
SIM_UNIVERSAL="$TARGET_DIR/ios-sim-universal/libuniffi_resvg_mobile.a"

mkdir -p "$(dirname "$SIM_UNIVERSAL")"
lipo -create "$SIM_ARM" "$SIM_X64" -output "$SIM_UNIVERSAL"

echo "==> Generating Swift bindings"
mkdir -p "$GEN_DIR"
cargo run -p resvg-mobile --features bindgen-cli --bin uniffi-bindgen -- generate \
  "$RUST_DIR/resvg-mobile/src/resvg_mobile.udl" \
  --language swift \
  --out-dir "$GEN_DIR"

# UniFFI emits a separate modulemap; SPM uses an umbrella header approach via FFI target.
HEADERS_DIR="$ROOT/ios/ResvgMobileFFI/include"
mkdir -p "$HEADERS_DIR"
cp "$GEN_DIR/resvg_mobileFFI.h" "$HEADERS_DIR/"
cp "$GEN_DIR/resvg_mobileFFI.modulemap" "$HEADERS_DIR/module.modulemap"

echo "==> Creating XCFramework"
rm -rf "$OUT_DIR"
xcodebuild -create-xcframework \
  -library "$IOS_LIB" -headers "$HEADERS_DIR" \
  -library "$SIM_UNIVERSAL" -headers "$HEADERS_DIR" \
  -output "$OUT_DIR"

echo "Done: $OUT_DIR"
