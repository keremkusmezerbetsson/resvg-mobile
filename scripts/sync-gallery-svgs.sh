#!/usr/bin/env bash
# Sync gallery app assets from examples/svg-set and the vendored resvg-test-suite.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/rust/resvg-mobile/tests/suite/vendor/resvg-test-suite/tests"
VENDOR_FONTS="$ROOT/rust/resvg-mobile/tests/suite/vendor/resvg-test-suite/fonts"
ANDROID_ASSETS="$ROOT/android/gallery/src/main/assets"
IOS_GALLERY="$ROOT/examples/ios-gallery/ResvgGallery"

if [[ ! -d "$VENDOR" ]]; then
  echo "error: resvg-test-suite not found — run ./scripts/fetch-test-suite.sh first" >&2
  exit 1
fi

echo "==> Android gallery assets"
rm -rf "$ANDROID_ASSETS/svg-set" "$ANDROID_ASSETS/resvg-suite" "$ANDROID_ASSETS/suite-fonts"
mkdir -p "$ANDROID_ASSETS/svg-set" "$ANDROID_ASSETS/resvg-suite"
cp "$ROOT/examples/svg-set/"*.svg "$ANDROID_ASSETS/svg-set/"
rsync -a --delete "$VENDOR/" "$ANDROID_ASSETS/resvg-suite/"
if [[ -d "$VENDOR_FONTS" ]]; then
  mkdir -p "$ANDROID_ASSETS/suite-fonts"
  rsync -a --delete --include='*.ttf' --include='*.otf' --exclude='*' "$VENDOR_FONTS/" "$ANDROID_ASSETS/suite-fonts/"
fi

echo "==> iOS gallery bundle resources"
rm -rf "$IOS_GALLERY/svg-set" "$IOS_GALLERY/resvg-suite" "$IOS_GALLERY/suite-fonts"
mkdir -p "$IOS_GALLERY/svg-set" "$IOS_GALLERY/resvg-suite"
cp "$ROOT/examples/svg-set/"*.svg "$IOS_GALLERY/svg-set/"
rsync -a --delete "$VENDOR/" "$IOS_GALLERY/resvg-suite/"
if [[ -d "$VENDOR_FONTS" ]]; then
  mkdir -p "$IOS_GALLERY/suite-fonts"
  rsync -a --delete --include='*.ttf' --include='*.otf' --exclude='*' "$VENDOR_FONTS/" "$IOS_GALLERY/suite-fonts/"
fi

count_android=$(find "$ANDROID_ASSETS" -name '*.svg' | wc -l | tr -d ' ')
count_ios=$(find "$IOS_GALLERY" \( -path '*/svg-set/*.svg' -o -path '*/resvg-suite/*.svg' \) | wc -l | tr -d ' ')
echo "Synced $count_android Android SVGs, $count_ios iOS SVGs"
