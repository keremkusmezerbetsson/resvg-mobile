#!/usr/bin/env bash
# Fetch the linebender/resvg-test-suite (MIT) into the Rust crate test vendor dir.
# The committed VENDOR.lock rev is the source of truth unless RESVG_TEST_SUITE_REV is set.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT/rust/resvg-mobile/tests/suite/vendor/resvg-test-suite"
LOCK_FILE="$ROOT/rust/resvg-mobile/tests/suite/VENDOR.lock"

# Fallback pin if VENDOR.lock is missing.
# https://github.com/linebender/resvg-test-suite
DEFAULT_REV="d8e064337faf01bc5a9579187a56dbdbe3eacc72"

LOCK_REV=""
if [[ -f "$LOCK_FILE" ]]; then
  LOCK_REV="$(grep -E '^rev=' "$LOCK_FILE" | head -1 | cut -d= -f2- | tr -d '[:space:]')"
fi

if [[ -n "${RESVG_TEST_SUITE_REV:-}" ]]; then
  REV="$RESVG_TEST_SUITE_REV"
elif [[ -n "$LOCK_REV" ]]; then
  REV="$LOCK_REV"
else
  REV="$DEFAULT_REV"
fi

mkdir -p "$(dirname "$VENDOR_DIR")"

if [[ -d "$VENDOR_DIR/.git" ]]; then
  git -C "$VENDOR_DIR" fetch --depth 1 origin "$REV"
  git -C "$VENDOR_DIR" checkout --detach "$REV"
else
  rm -rf "$VENDOR_DIR"
  git clone --depth 1 https://github.com/linebender/resvg-test-suite.git "$VENDOR_DIR"
  git -C "$VENDOR_DIR" fetch --depth 1 origin "$REV"
  git -C "$VENDOR_DIR" checkout --detach "$REV"
fi

ACTUAL="$(git -C "$VENDOR_DIR" rev-parse HEAD)"
if [[ "$ACTUAL" != "$REV" ]]; then
  echo "error: resvg-test-suite checkout is $ACTUAL, expected $REV" >&2
  exit 1
fi

if [[ "$LOCK_REV" != "$REV" ]]; then
  cat >"$LOCK_FILE" <<EOF
# linebender/resvg-test-suite — MIT license
# https://github.com/linebender/resvg-test-suite
rev=$REV
EOF
fi

SVG_COUNT="$(find "$VENDOR_DIR/tests" -name '*.svg' 2>/dev/null | wc -l | tr -d ' ')"
echo "Fetched resvg-test-suite @ ${REV:0:12} ($SVG_COUNT SVG files under tests/)"
echo "Run ./scripts/sync-gallery-svgs.sh to copy the suite into the gallery demo apps."
