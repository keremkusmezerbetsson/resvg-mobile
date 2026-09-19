#!/usr/bin/env bash
# Build libuniffi_resvg_mobile.so for all (or one) size variants into flavor jniLibs dirs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_DIR="$ROOT/rust"
OUT_ROOT="$ROOT/android/resvg-mobile/src"

VARIANT="${VARIANT:-all}"

cargo_features_for() {
  case "$1" in
    full) echo "--features text,images" ;;
    no-images) echo "--no-default-features --features text" ;;
    no-text) echo "--no-default-features --features images" ;;
    minimal) echo "--no-default-features" ;;
    *)
      echo "unknown variant: $1 (full|no-images|no-text|minimal|all)" >&2
      exit 1
      ;;
  esac
}

flavor_dir_for() {
  case "$1" in
    full) echo "full" ;;
    no-images) echo "noImages" ;;
    no-text) echo "noText" ;;
    minimal) echo "minimal" ;;
  esac
}

build_one() {
  local variant="$1"
  local flavor
  flavor="$(flavor_dir_for "$variant")"
  local out="$OUT_ROOT/$flavor/jniLibs"
  local features
  features="$(cargo_features_for "$variant")"
  mkdir -p "$out"
  echo "==> Android $variant → $out ($features)"
  # shellcheck disable=SC2086
  (cd "$RUST_DIR" && cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 \
    -o "$out" \
    build -p resvg-mobile --release $features)
  ls -lh "$out"/*/libuniffi_resvg_mobile.so
}

if [[ "$VARIANT" == "all" ]]; then
  for v in full no-images no-text minimal; do
    build_one "$v"
  done
else
  build_one "$VARIANT"
fi

echo "Done."
