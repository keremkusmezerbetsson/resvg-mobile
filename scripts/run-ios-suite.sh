#!/usr/bin/env bash
# Run iOS SVG suite on the simulator and copy results JSONL.
# Usage: MANIFEST=smoke|full ./scripts/run-ios-suite.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${MANIFEST:-smoke}"
OUT_DIR="${SUITE_OUT_DIR:-$ROOT/artifacts/suite}"
DUMP_MISMATCH="${DUMP_MISMATCH:-0}"
RESULTS="$OUT_DIR/ios-results.jsonl"
DERIVED="${SUITE_DERIVED_DATA:-/tmp/ResvgMobile-Suite}"
SIM_RESULTS="/tmp/ios-results.jsonl"

mkdir -p "$OUT_DIR"
"$ROOT/scripts/sync-suite-assets.sh" "$MANIFEST"

if [[ ! -d "$ROOT/ios/ResvgMobileFFI.xcframework" ]] || \
   [[ ! -f "$ROOT/ios/ResvgMobileFFI.xcframework/Info.plist" ]]; then
  echo "==> Building XCFramework (VARIANT=full)"
  VARIANT=full "$ROOT/rust/build-ios.sh"
fi

resolve_udid() {
  if [[ -n "${SUITE_DESTINATION:-}" && "$SUITE_DESTINATION" == *id=* ]]; then
    echo "$SUITE_DESTINATION" | sed -E 's/.*id=([^,]+).*/\1/'
    return
  fi
  local booted
  booted="$(xcrun simctl list devices booted 2>/dev/null | grep -E 'iPhone' | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' || true)"
  if [[ -n "$booted" ]]; then
    echo "$booted"
    return
  fi
  local want_name line
  if [[ -n "${SUITE_DESTINATION:-}" && "$SUITE_DESTINATION" == *name=* ]]; then
    want_name="$(echo "$SUITE_DESTINATION" | sed -E 's/.*name=([^,]+).*/\1/')"
    line="$(xcrun simctl list devices available 2>/dev/null | grep -F "$want_name (" | head -1 || true)"
  else
    line="$(xcrun simctl list devices available 2>/dev/null | grep -E 'iPhone' | head -1 || true)"
  fi
  if [[ -n "$line" ]]; then
    echo "$line" | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/'
    return
  fi
  echo ""
}

UDID="$(resolve_udid)"
if [[ -z "$UDID" ]]; then
  echo "No iOS Simulator UDID found" >&2
  exit 1
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
DESTINATION="platform=iOS Simulator,id=$UDID"

export SIMCTL_CHILD_DUMP_MISMATCH="$DUMP_MISMATCH"
export SIMCTL_CHILD_SUITE_RESULTS_PATH="$SIM_RESULTS"
if [[ "$DUMP_MISMATCH" == "1" ]]; then
  export SIMCTL_CHILD_SUITE_DUMP_DIR="/tmp/resvg-suite-pixels"
fi

echo "==> xcodebuild test ResvgMobileSuiteTests ($MANIFEST) → $DESTINATION"
(
  cd "$ROOT/ios"
  xcodebuild test \
    -scheme ResvgMobile-Package \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED" \
    -only-testing:ResvgMobileSuiteTests/SuiteRenderTests/testRenderSuiteAndWriteResults \
    CODE_SIGNING_ALLOWED=NO
)

echo "==> Collecting ios-results.jsonl"
# XCTest often writes /tmp on the host (not the guest); prefer that, then sim paths.
if [[ -s /tmp/ios-results.jsonl ]]; then
  cp /tmp/ios-results.jsonl "$RESULTS"
elif xcrun simctl spawn "$UDID" cat "$SIM_RESULTS" >"$RESULTS" 2>/dev/null && [[ -s "$RESULTS" ]]; then
  :
else
  rm -f "$RESULTS"
  FOUND="$(find "$HOME/Library/Developer/CoreSimulator/Devices/$UDID" -name 'ios-results.jsonl' 2>/dev/null | head -1 || true)"
  if [[ -n "$FOUND" && -s "$FOUND" ]]; then
    cp "$FOUND" "$RESULTS"
  else
    echo "Could not locate ios-results.jsonl (host /tmp or simulator $UDID)" >&2
    exit 1
  fi
fi

if [[ "$DUMP_MISMATCH" == "1" ]]; then
  mkdir -p "$OUT_DIR/pixels/ios"
  HOST_TMP="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/tmp/resvg-suite-pixels"
  if [[ -d "$HOST_TMP" ]]; then
    cp -R "$HOST_TMP"/. "$OUT_DIR/pixels/ios/" || true
  fi
fi

if [[ ! -f "$RESULTS" ]] || [[ ! -s "$RESULTS" ]]; then
  echo "ios-results.jsonl missing or empty at $RESULTS" >&2
  exit 1
fi

echo "Wrote $RESULTS ($(wc -l <"$RESULTS" | tr -d ' ') lines)"
