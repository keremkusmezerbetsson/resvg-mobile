#!/usr/bin/env bash
# Fetch the linebender/resvg-test-suite (MIT) into the Rust crate test vendor dir.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT/rust/resvg-mobile/tests/suite/vendor/resvg-test-suite"
LOCK_FILE="$ROOT/rust/resvg-mobile/tests/suite/VENDOR.lock"

# Pinned commit from https://github.com/linebender/resvg-test-suite
DEFAULT_REV="d8e064337faf01bc5a9579187a56dbdbe3eacc72"
REV="${RESVG_TEST_SUITE_REV:-$DEFAULT_REV}"

mkdir -p "$(dirname "$VENDOR_DIR")"

if [[ -d "$VENDOR_DIR/.git" ]]; then
  git -C "$VENDOR_DIR" fetch --depth 1 origin "$REV" 2>/dev/null || true
  git -C "$VENDOR_DIR" checkout --detach "$REV"
else
  rm -rf "$VENDOR_DIR"
  git clone --depth 1 https://github.com/linebender/resvg-test-suite.git "$VENDOR_DIR"
  git -C "$VENDOR_DIR" fetch --depth 1 origin "$REV"
  git -C "$VENDOR_DIR" checkout --detach "$REV"
fi

cat >"$LOCK_FILE" <<EOF
# linebender/resvg-test-suite — MIT license
# https://github.com/linebender/resvg-test-suite
rev=$REV
EOF

SVG_COUNT="$(find "$VENDOR_DIR/tests" -name '*.svg' 2>/dev/null | wc -l | tr -d ' ')"
echo "Fetched resvg-test-suite @ ${REV:0:12} ($SVG_COUNT SVG files under tests/)"
echo "Run ./scripts/sync-gallery-svgs.sh to copy the suite into the gallery demo apps."
