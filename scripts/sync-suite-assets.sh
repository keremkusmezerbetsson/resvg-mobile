#!/usr/bin/env bash
# Sync resvg-test-suite fixtures into Android/iOS suite harness asset trees.
# Usage: ./scripts/sync-suite-assets.sh [smoke|full]
#
# Layout (mirrors vendor so ../../../resources from suite/structure/image works):
#   <root>/suite/<rel>.svg
#   <root>/resources/*          # vendor resources/ (external image hrefs)
#   <root>/suite-fonts/*        # full only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${1:-${MANIFEST:-smoke}}"
VENDOR="$ROOT/rust/resvg-mobile/tests/suite/vendor/resvg-test-suite"
TESTS="$VENDOR/tests"
RESOURCES="$VENDOR/resources"
FONTS="$VENDOR/fonts"
SMOKE_LIST="$ROOT/rust/resvg-mobile/tests/suite/smoke.txt"

ANDROID_ASSETS="$ROOT/android/resvg-mobile/src/androidTest/assets"
IOS_FIXTURES="$ROOT/ios/Tests/ResvgMobileSuiteTests/Fixtures"

if [[ ! -d "$TESTS" ]]; then
  echo "==> Fetching test suite"
  "$ROOT/scripts/fetch-test-suite.sh"
fi

copy_rel() {
  local rel="$1"
  local src="$TESTS/$rel"
  if [[ ! -f "$src" ]]; then
    echo "MISSING $rel" >&2
    return 1
  fi
  for dest_root in "$ANDROID_ASSETS/suite" "$IOS_FIXTURES/suite"; do
    local dest="$dest_root/$rel"
    mkdir -p "$(dirname "$dest")"
    # Atomic-ish replace avoids races when sync is invoked twice concurrently.
    local tmp="${dest}.tmp.$$"
    cp -f "$src" "$tmp"
    mv -f "$tmp" "$dest"
  done
}

sync_resources() {
  if [[ ! -d "$RESOURCES" ]]; then
    return 0
  fi
  mkdir -p "$ANDROID_ASSETS/resources" "$IOS_FIXTURES/resources"
  rsync -a --delete "$RESOURCES"/ "$ANDROID_ASSETS/resources/"
  rsync -a --delete "$RESOURCES"/ "$IOS_FIXTURES/resources/"
}

echo "==> Syncing $MANIFEST suite assets"
rm -rf "$ANDROID_ASSETS/suite" "$ANDROID_ASSETS/suite-fonts" "$ANDROID_ASSETS/resources"
rm -rf "$IOS_FIXTURES/suite" "$IOS_FIXTURES/suite-fonts" "$IOS_FIXTURES/resources"
mkdir -p "$ANDROID_ASSETS/suite" "$IOS_FIXTURES/suite"

case "$MANIFEST" in
  smoke)
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="$(echo "$line" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$line" ]] && continue
      copy_rel "$line"
    done <"$SMOKE_LIST"
    mkdir -p "$ANDROID_ASSETS" "$IOS_FIXTURES"
    cp -f "$SMOKE_LIST" "$ANDROID_ASSETS/smoke.txt"
    cp -f "$SMOKE_LIST" "$IOS_FIXTURES/smoke.txt"
    sync_resources
    ;;
  full)
    (cd "$TESTS" && find . -name '*.svg' -type f | sed 's|^\./||' | while read -r rel; do
      copy_rel "$rel"
    done)
    touch "$ANDROID_ASSETS/full.marker"
    touch "$IOS_FIXTURES/full.marker"
    sync_resources
    if [[ -d "$FONTS" ]]; then
      mkdir -p "$ANDROID_ASSETS/suite-fonts" "$IOS_FIXTURES/suite-fonts"
      rsync -a --delete "$FONTS"/ "$ANDROID_ASSETS/suite-fonts/"
      rsync -a --delete "$FONTS"/ "$IOS_FIXTURES/suite-fonts/"
    fi
    ;;
  *)
    echo "Usage: $0 smoke|full" >&2
    exit 1
    ;;
esac

echo "$MANIFEST" >"$ANDROID_ASSETS/manifest.txt"
echo "$MANIFEST" >"$IOS_FIXTURES/manifest.txt"

SVG_COUNT="$(find "$ANDROID_ASSETS/suite" -name '*.svg' 2>/dev/null | wc -l | tr -d ' ')"
RES_COUNT="$(find "$ANDROID_ASSETS/resources" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "Synced $SVG_COUNT SVGs + $RES_COUNT resource files → Android androidTest assets + iOS Fixtures ($MANIFEST)"
