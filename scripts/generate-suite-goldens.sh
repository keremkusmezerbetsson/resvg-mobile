#!/usr/bin/env bash
# Generate suite golden JSONL files (SHA-256 of straight RGBA @ 512 Contain).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${1:-${MANIFEST:-smoke}}"
OUT_DIR="$ROOT/rust/resvg-mobile/tests/suite/goldens"
DUMP_DIR="${SUITE_DUMP_DIR:-}"

if [[ ! -d "$ROOT/rust/resvg-mobile/tests/suite/vendor/resvg-test-suite/tests" ]]; then
  echo "==> Fetching test suite"
  "$ROOT/scripts/fetch-test-suite.sh"
fi

mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/${MANIFEST}.jsonl"

ARGS=(run -p resvg-mobile --bin suite-goldens -- --manifest "$MANIFEST" --out "$OUT")
if [[ -n "$DUMP_DIR" ]]; then
  mkdir -p "$DUMP_DIR"
  ARGS+=(--dump-dir "$DUMP_DIR")
fi

echo "==> Generating $MANIFEST goldens → $OUT"
(cd "$ROOT/rust" && cargo "${ARGS[@]}")
echo "Done: $OUT"
