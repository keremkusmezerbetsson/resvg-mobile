# SVG conformance + cross-platform suite

This crate runs integration tests against the official **[linebender/resvg-test-suite](https://github.com/linebender/resvg-test-suite)** (MIT, ~1,679 SVG files). That suite is maintained for the [resvg](https://github.com/linebender/resvg) renderer and is the best match for resvg-mobile.

Cross-platform comparison reuses the same fixtures: Rust host goldens, Android emulator, and iOS simulator all render with a shared contract (**512×512**, `FitMode::Contain`, transparent background) and hash **straight RGBA** with SHA-256.

## Setup

From the repository root:

```bash
chmod +x scripts/fetch-test-suite.sh
./scripts/fetch-test-suite.sh
```

Fixtures are cloned to `tests/suite/vendor/resvg-test-suite/` (gitignored). The pinned revision is recorded in `VENDOR.lock`.

## Rust goldens

```bash
./scripts/generate-suite-goldens.sh smoke   # → goldens/smoke.jsonl (committed)
./scripts/generate-suite-goldens.sh full    # → goldens/full.jsonl (gitignored)
```

Optional RGBA dumps for fuzzy compare: `SUITE_DUMP_DIR=artifacts/suite/pixels/golden ./scripts/generate-suite-goldens.sh smoke`

## Running Rust tests

**Smoke subset** (~57 curated cases, runs in CI; asserts hashes vs `goldens/smoke.jsonl`):

```bash
cd rust
cargo test -p resvg-mobile --test svg_suite smoke_suite_renders
```

**Full vendor suite** (~1,679 SVGs; ~1,676 render; optional):

```bash
RESVG_RUN_FULL_SUITE=1 cargo test -p resvg-mobile --test svg_suite full_suite_renders
```

If `goldens/full.jsonl` is present, full suite also asserts hashes; otherwise it only gates on a ≤2% render failure rate. Three vendor files are known parse failures (`negative-size`, `not-UTF-8`, `zero-size`) and count toward that gate.

## Android + iOS harnesses

```bash
./scripts/sync-suite-assets.sh smoke   # or full
MANIFEST=smoke ./scripts/run-android-suite.sh   # needs emulator + adb
MANIFEST=smoke ./scripts/run-ios-suite.sh       # needs XCFramework + simulator
```

Results land under `artifacts/suite/{android,ios}-results.jsonl`.

### Synced asset layout

`sync-suite-assets.sh` mirrors vendor paths into Android `androidTest/assets` and iOS `Fixtures` (both gitignored except README / `manifest.txt`):

| Path | Smoke | Full | Role |
| ---- | ----- | ---- | ---- |
| `suite/**/*.svg` | curated list from `smoke.txt` | all vendor `tests/**/*.svg` | Inputs to render |
| `resources/` | yes | yes | External image href targets (`../../../resources/…`) |
| `suite-fonts/` | no | yes (when vendor `fonts/` exists) | Font files for text cases |
| `smoke.txt` / `manifest.txt` | yes | `manifest.txt` + `full.marker` | Harness mode |

Vendor `tests/**/*.png` are **result goldens** from upstream, not inputs — they are intentionally **not** synced. Raster inputs live under vendor `resources/`.

### `resources_dir` / UniFFI

Relative image hrefs resolve via UniFFI `render_with_resources(..., resources_dir?)`:

- **Android:** assets are extracted to disk; harness passes the SVG’s parent directory as `resources_dir` (so `../../../resources` from e.g. `suite/structure/image/` reaches the sibling `resources/` tree).
- **iOS:** Fixtures keep the same layout; harness passes the SVG parent path the same way.

Requires the Cargo `images` feature (default / full mobile variant). Empty `FontConfig` for smoke (no text category yet). Full suite also loads `suite-fonts/` when present.

Smoke cases cover shapes, painting, structure (embedded + external rasters), paint servers, masking, and filters.

Full harnesses use the same ≤2% render-failure gate as Rust (smoke: zero failures).

### Full local run

```bash
./scripts/sync-suite-assets.sh full
MANIFEST=full ./scripts/run-android-suite.sh
MANIFEST=full ./scripts/run-ios-suite.sh
./scripts/compare-suite-results.py \
  --golden rust/resvg-mobile/tests/suite/goldens/full.jsonl \
  --android artifacts/suite/android-results.jsonl \
  --ios artifacts/suite/ios-results.jsonl \
  --soft-pass --max-abs 1 --pct-diff 0.01
```

(`full.jsonl` from `./scripts/generate-suite-goldens.sh full`; nightly-style compare uses `--soft-pass`.)

## Compare (exact SHA + fuzzy)

```bash
./scripts/compare-suite-results.py \
  --golden rust/resvg-mobile/tests/suite/goldens/smoke.jsonl \
  --android artifacts/suite/android-results.jsonl \
  --ios artifacts/suite/ios-results.jsonl
```

On SHA mismatch, pass `--android-dump` / `--ios-dump` / `--golden-dump` directories of `*.rgba` dumps (from `DUMP_MISMATCH=1` or `SUITE_DUMP_DIR`). Nightly soft-pass:

```bash
./scripts/compare-suite-results.py ... --soft-pass --max-abs 1 --pct-diff 0.01
```

Fuzzy metrics: max absolute channel error, MAE, % pixels with any channel Δ≥1, RMSE. Diff PNGs go to `artifacts/suite/diffs/`.

## Manifests

| File | Purpose |
| ---- | ------- |
| `smoke.txt` | Curated paths relative to `vendor/.../tests/` — strict pass/fail in CI |
| `goldens/smoke.jsonl` | Committed SHA-256 goldens for smoke |
| `goldens/full.jsonl` | Regenerated locally / nightly (gitignored) |
| `VENDOR.lock` | Pinned upstream commit SHA |

## Updating the upstream pin

1. Pick a commit from [resvg-test-suite](https://github.com/linebender/resvg-test-suite).
2. `RESVG_TEST_SUITE_REV=<sha> ./scripts/fetch-test-suite.sh`
3. Regenerate smoke goldens and re-run smoke + full suite before committing `VENDOR.lock` + `goldens/smoke.jsonl`.

## Alternative: W3C SVG 1.1 Test Suite

The archived [W3C SVG 1.1 Second Edition Test Suite](https://www.w3.org/Graphics/SVG/Test/2011/build/) is larger and browser-oriented. resvg-test-suite is preferred here because it targets resvg directly and has a simpler layout for automated rendering.
