#!/usr/bin/env bash
# Build an XCFramework for iOS device + simulator and regenerate Swift bindings.
#
# Usage:
#   ./rust/build-ios.sh                  # full (default) → ios/ResvgMobileFFI.xcframework
#   VARIANT=minimal ./rust/build-ios.sh  # one variant under ios/variants/<name>/
#   VARIANT=all ./rust/build-ios.sh      # all four variants + copy full to default path
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_DIR="$ROOT/rust"
GEN_DIR="$ROOT/ios/Sources/ResvgMobile/Generated"
TARGET_DIR="${CARGO_TARGET_DIR:-$RUST_DIR/target}"
VARIANT="${VARIANT:-full}"

cargo_features_for() {
  case "$1" in
    full) echo "--features text,images" ;;
    no-images) echo "--no-default-features --features text" ;;
    no-text) echo "--no-default-features --features images" ;;
    minimal) echo "--no-default-features" ;;
    *)
      echo "unknown VARIANT=$1 (full|no-images|no-text|minimal|all)" >&2
      exit 1
      ;;
  esac
}

cd "$RUST_DIR"

TARGETS=(
  aarch64-apple-ios
  aarch64-apple-ios-sim
  x86_64-apple-ios
)

for t in "${TARGETS[@]}"; do
  rustup target add "$t" >/dev/null
done

build_variant() {
  local variant="$1"
  local features
  features="$(cargo_features_for "$variant")"
  local out_dir
  if [[ "$variant" == "full" && "${COPY_FULL_TO_DEFAULT:-1}" == "1" && "$VARIANT" != "all" ]]; then
    out_dir="$ROOT/ios/ResvgMobileFFI.xcframework"
  else
    out_dir="$ROOT/ios/variants/$variant/ResvgMobileFFI.xcframework"
  fi

  echo "==> Building staticlibs ($variant: $features)"
  # shellcheck disable=SC2086
  cargo build -p resvg-mobile --release --target aarch64-apple-ios $features
  # shellcheck disable=SC2086
  cargo build -p resvg-mobile --release --target aarch64-apple-ios-sim $features
  # shellcheck disable=SC2086
  cargo build -p resvg-mobile --release --target x86_64-apple-ios $features

  local ios_lib="$TARGET_DIR/aarch64-apple-ios/release/libuniffi_resvg_mobile.a"
  local sim_arm="$TARGET_DIR/aarch64-apple-ios-sim/release/libuniffi_resvg_mobile.a"
  local sim_x64="$TARGET_DIR/x86_64-apple-ios/release/libuniffi_resvg_mobile.a"
  local sim_universal="$TARGET_DIR/ios-sim-universal-$variant/libuniffi_resvg_mobile.a"

  mkdir -p "$(dirname "$sim_universal")"
  lipo -create "$sim_arm" "$sim_x64" -output "$sim_universal"

  local headers_dir="$ROOT/ios/ResvgMobileFFI/include"
  mkdir -p "$headers_dir"
  if [[ ! -f "$headers_dir/resvg_mobileFFI.h" ]]; then
    echo "==> Generating Swift bindings (headers)"
    mkdir -p "$GEN_DIR"
    cargo run -p resvg-mobile --features bindgen-cli --bin uniffi-bindgen -- generate \
      "$RUST_DIR/resvg-mobile/src/resvg_mobile.udl" \
      --language swift \
      --out-dir "$GEN_DIR"
    cp "$GEN_DIR/resvg_mobileFFI.h" "$headers_dir/"
    cp "$GEN_DIR/resvg_mobileFFI.modulemap" "$headers_dir/module.modulemap"
  fi

  echo "==> Creating XCFramework → $out_dir"
  rm -rf "$out_dir"
  mkdir -p "$(dirname "$out_dir")"
  xcodebuild -create-xcframework \
    -library "$ios_lib" -headers "$headers_dir" \
    -library "$sim_universal" -headers "$headers_dir" \
    -output "$out_dir"

  local default_out="$ROOT/ios/ResvgMobileFFI.xcframework"
  # Always also refresh the default full path when building full as part of `all`.
  if [[ "$variant" == "full" && "$VARIANT" == "all" ]]; then
    rm -rf "$default_out"
    cp -R "$out_dir" "$default_out"
    echo "Copied full → $default_out"
  fi

  if [[ -f "$ROOT/ios/ResvgMobileFFI.BUILD.md" && -d "$default_out" ]]; then
    cp "$ROOT/ios/ResvgMobileFFI.BUILD.md" "$default_out/BUILD.md"
  fi

  echo "Done: $out_dir"
}

# Generate bindings once up front (shared UDL surface for all variants).
echo "==> Generating Swift bindings"
mkdir -p "$GEN_DIR"
cargo run -p resvg-mobile --features bindgen-cli --bin uniffi-bindgen -- generate \
  "$RUST_DIR/resvg-mobile/src/resvg_mobile.udl" \
  --language swift \
  --out-dir "$GEN_DIR"
HEADERS_DIR="$ROOT/ios/ResvgMobileFFI/include"
mkdir -p "$HEADERS_DIR"
cp "$GEN_DIR/resvg_mobileFFI.h" "$HEADERS_DIR/"
cp "$GEN_DIR/resvg_mobileFFI.modulemap" "$HEADERS_DIR/module.modulemap"

if [[ "$VARIANT" == "all" ]]; then
  for v in full no-images no-text minimal; do
    build_variant "$v"
  done
else
  build_variant "$VARIANT"
fi
