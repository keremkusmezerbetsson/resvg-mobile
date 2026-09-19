#!/usr/bin/env bash
# Run Android SVG suite on a connected emulator/device and pull results JSONL.
# Usage: MANIFEST=smoke|full ./scripts/run-android-suite.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${MANIFEST:-smoke}"
OUT_DIR="${SUITE_OUT_DIR:-$ROOT/artifacts/suite}"
DUMP_MISMATCH="${DUMP_MISMATCH:-0}"
PKG_CANDIDATES=("com.resvg.mobile" "com.resvg.mobile.test")

mkdir -p "$OUT_DIR"
"$ROOT/scripts/sync-suite-assets.sh" "$MANIFEST"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found (Android SDK platform-tools)" >&2
  exit 1
fi

adb wait-for-device
adb devices | grep -E $'\tdevice$' >/dev/null || {
  echo "No Android device/emulator in 'device' state" >&2
  exit 1
}

# Clear stale public results so the harness can rewrite (scoped storage).
adb shell "rm -rf /sdcard/Download/resvg-suite" 2>/dev/null || true

echo "==> connectedFullDebugAndroidTest ($MANIFEST)"
(
  cd "$ROOT/android"
  ./gradlew :resvg-mobile:connectedFullDebugAndroidTest \
    -Pandroid.testInstrumentationRunnerArguments.DUMP_MISMATCH="$DUMP_MISMATCH"
)

echo "==> Pulling android-results.jsonl"
RESULTS="$OUT_DIR/android-results.jsonl"
# Prefer public Downloads copy (survives test APK uninstall / scoped storage).
CANDIDATES=(
  "/sdcard/Download/resvg-suite/android-results.jsonl"
)
for pkg in "${PKG_CANDIDATES[@]}"; do
  CANDIDATES+=(
    "/sdcard/Android/data/${pkg}/files/android-results.jsonl"
    "/storage/emulated/0/Android/data/${pkg}/files/android-results.jsonl"
  )
done

pulled=0
for remote in "${CANDIDATES[@]}"; do
  if adb shell "test -f '$remote'" 2>/dev/null; then
    adb pull "$remote" "$RESULTS"
    pulled=1
    break
  fi
done

if [[ "$pulled" -ne 1 ]]; then
  FOUND="$(adb shell "find /sdcard -name android-results.jsonl 2>/dev/null" | tr -d '\r' | head -1 || true)"
  if [[ -n "$FOUND" ]]; then
    adb pull "$FOUND" "$RESULTS"
    pulled=1
  fi
fi

if [[ "$pulled" -ne 1 || ! -f "$RESULTS" ]]; then
  echo "Failed to pull android-results.jsonl" >&2
  exit 1
fi

if [[ "$DUMP_MISMATCH" == "1" ]]; then
  mkdir -p "$OUT_DIR/pixels/android"
  for pkg in "${PKG_CANDIDATES[@]}"; do
    remote="/sdcard/Android/data/${pkg}/files/pixels"
    if adb shell "test -d '$remote'" 2>/dev/null; then
      adb pull "$remote/." "$OUT_DIR/pixels/android/" || true
      break
    fi
  done
  if adb shell "test -d '/sdcard/Download/resvg-suite/pixels'" 2>/dev/null; then
    adb pull "/sdcard/Download/resvg-suite/pixels/." "$OUT_DIR/pixels/android/" || true
  fi
fi

echo "Wrote $RESULTS ($(wc -l <"$RESULTS" | tr -d ' ') lines)"
