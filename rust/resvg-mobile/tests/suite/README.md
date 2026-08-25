# SVG conformance tests

This crate runs integration tests against the official **[linebender/resvg-test-suite](https://github.com/linebender/resvg-test-suite)** (MIT, ~1,679 SVG files). That suite is maintained for the [resvg](https://github.com/linebender/resvg) renderer and is the best match for resvg-mobile.

## Setup

From the repository root:

```bash
chmod +x scripts/fetch-test-suite.sh
./scripts/fetch-test-suite.sh
```

Fixtures are cloned to `tests/suite/vendor/resvg-test-suite/` (gitignored). The pinned revision is recorded in `VENDOR.lock`.

## Running tests

**Smoke subset** (~48 curated cases, runs in CI):

```bash
cd rust
cargo test -p resvg-mobile --test svg_suite smoke_suite_renders
```

**Full vendor suite** (~1,600+ self-contained SVGs; optional, slower):

```bash
RESVG_RUN_FULL_SUITE=1 cargo test -p resvg-mobile --test svg_suite full_suite_renders
```

## Manifests

| File | Purpose |
|------|---------|
| `smoke.txt` | Curated paths relative to `vendor/.../tests/` — strict pass/fail in CI |
| `VENDOR.lock` | Pinned upstream commit SHA |

Smoke cases are chosen to cover shapes, painting, structure, paint servers, masking, and filters without external image/font dependencies.

## Updating the upstream pin

1. Pick a commit from [resvg-test-suite](https://github.com/linebender/resvg-test-suite).
2. `RESVG_TEST_SUITE_REV=<sha> ./scripts/fetch-test-suite.sh`
3. Re-run smoke + full suite locally before committing `VENDOR.lock`.

## Alternative: W3C SVG 1.1 Test Suite

The archived [W3C SVG 1.1 Second Edition Test Suite](https://www.w3.org/Graphics/SVG/Test/2011/build/) is larger and browser-oriented. resvg-test-suite is preferred here because it targets resvg directly and has a simpler layout for automated rendering.
