#!/usr/bin/env bash
# CI / local orchestration: Rust tests + UniFFI codegen + optional mobile packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/rust"

echo "==> Rust tests"
cargo test -p resvg-mobile

echo "==> Regenerate bindings"
mkdir -p "$ROOT/ios/Sources/ResvgMobile/Generated"
cargo run -p resvg-mobile --features bindgen-cli --bin uniffi-bindgen -- generate \
  "$ROOT/rust/resvg-mobile/src/resvg_mobile.udl" \
  --language swift \
  --config "$ROOT/rust/resvg-mobile/uniffi.toml" \
  --out-dir "$ROOT/ios/Sources/ResvgMobile/Generated"

mkdir -p "$ROOT/android/resvg-mobile/src/main/java"
cargo run -p resvg-mobile --features bindgen-cli --bin uniffi-bindgen -- generate \
  "$ROOT/rust/resvg-mobile/src/resvg_mobile.udl" \
  --language kotlin \
  --config "$ROOT/rust/resvg-mobile/uniffi.toml" \
  --out-dir "$ROOT/android/resvg-mobile/src/main/java" \
  --no-format

if [[ "${BUILD_IOS:-0}" == "1" ]]; then
  echo "==> iOS XCFramework"
  "$ROOT/rust/build-ios.sh"
fi

if [[ "${BUILD_ANDROID:-0}" == "1" ]]; then
  echo "==> Android AAR (requires NDK + cargo-ndk)"
  if ! command -v cargo-ndk >/dev/null; then
    echo "error: cargo-ndk is required when BUILD_ANDROID=1" >&2
    exit 1
  fi
  VARIANT="${VARIANT:-all}" "$ROOT/scripts/build-android-variants.sh"
  (cd "$ROOT/android" && ./gradlew \
    :resvg-mobile:assembleFullRelease \
    :resvg-mobile:assembleNoImagesRelease \
    :resvg-mobile:assembleNoTextRelease \
    :resvg-mobile:assembleMinimalRelease \
    :resvg-mobile-ui:assembleRelease \
    :resvg-mobile-coil:assembleRelease)
fi

echo "OK"
