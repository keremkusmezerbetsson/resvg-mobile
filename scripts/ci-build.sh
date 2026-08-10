#!/usr/bin/env bash
# CI / local orchestration: Rust tests + UniFFI codegen + optional mobile packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/rust"

echo "==> Rust tests"
cargo test -p resvg-mobile

echo "==> Regenerate bindings"
mkdir -p "$ROOT/ios/Sources/ResvgMobile/Generated"
cargo run -p resvg-mobile --bin uniffi-bindgen -- generate \
  "$ROOT/rust/resvg-mobile/src/resvg_mobile.udl" \
  --language swift \
  --config "$ROOT/rust/resvg-mobile/uniffi.toml" \
  --out-dir "$ROOT/ios/Sources/ResvgMobile/Generated"

mkdir -p "$ROOT/android/resvg-mobile/src/main/java"
cargo run -p resvg-mobile --bin uniffi-bindgen -- generate \
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
  if command -v cargo-ndk >/dev/null; then
    cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 \
      -o "$ROOT/android/resvg-mobile/src/main/jniLibs" \
      build -p resvg-mobile --release
  fi
  (cd "$ROOT/android" && ./gradlew :resvg-mobile:assembleRelease :resvg-mobile-ui:assembleRelease)
fi

echo "OK"
