//! Integration tests against [linebender/resvg-test-suite](https://github.com/linebender/resvg-test-suite).
//!
//! Fetch fixtures first:
//! ```text
//! ./scripts/fetch-test-suite.sh
//! ```
//!
//! Run the full vendor suite locally (slow):
//! ```text
//! RESVG_RUN_FULL_SUITE=1 cargo test -p resvg-mobile --test svg_suite
//! ```

use std::path::{Path, PathBuf};

use uniffi_resvg_mobile::{render_file, FitMode, RenderOptions, ResvgError, Rgba, MAX_DIMENSION, MAX_PIXELS};

const SUITE_TESTS: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/tests/suite/vendor/resvg-test-suite/tests"
);

fn suite_tests_dir() -> PathBuf {
    PathBuf::from(SUITE_TESTS)
}

fn require_suite() -> PathBuf {
    let root = suite_tests_dir();
    assert!(
        root.is_dir(),
        "resvg-test-suite not found at {} — run ./scripts/fetch-test-suite.sh",
        root.display()
    );
    root
}

fn load_manifest(name: &str) -> Vec<String> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/suite")
        .join(name);
    let text = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(str::to_string)
        .collect()
}

fn suite_render_options() -> RenderOptions {
    // Prefer intrinsic when it fits our memory budget; otherwise letterbox.
    let side = 512u32;
    RenderOptions {
        width: Some(side),
        height: Some(side),
        fit: FitMode::Contain,
        background: Some(Rgba {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        }),
    }
}

fn assert_renders(path: &Path) {
    let img = render_file(path, suite_render_options(), Vec::new()).unwrap_or_else(|e| {
        panic!("failed to render {}: {e:?}", path.display());
    });
    assert!(img.width > 0 && img.height > 0, "zero output: {}", path.display());
    assert!(
        img.width <= MAX_DIMENSION && img.height <= MAX_DIMENSION,
        "edge cap exceeded: {}",
        path.display()
    );
    let pixels = (img.width as u64).saturating_mul(img.height as u64);
    assert!(
        pixels <= MAX_PIXELS as u64,
        "pixel budget exceeded: {}",
        path.display()
    );
    assert_eq!(
        img.rgba.len(),
        (img.width as usize) * (img.height as usize) * 4,
        "rgba length mismatch: {}",
        path.display()
    );
}

#[test]
fn smoke_suite_renders() {
    let root = require_suite();
    let rel_paths = load_manifest("smoke.txt");
    assert!(
        rel_paths.len() >= 40,
        "smoke manifest should list ~48 cases, got {}",
        rel_paths.len()
    );

    for rel in rel_paths {
        let path = root.join(&rel);
        assert!(path.is_file(), "missing smoke fixture: {}", path.display());
        assert_renders(&path);
    }
}

#[test]
fn full_suite_renders() {
    if std::env::var("RESVG_RUN_FULL_SUITE").ok().as_deref() != Some("1") {
        eprintln!("Skipping full suite (set RESVG_RUN_FULL_SUITE=1 to enable)");
        return;
    }

    let root = require_suite();
    let mut paths = Vec::new();
    collect_svgs(&root, &mut paths);
    paths.sort();

    let mut ok = 0usize;
    let mut failures: Vec<(PathBuf, ResvgError)> = Vec::new();

    for path in paths {
        match render_file(&path, suite_render_options(), Vec::new()) {
            Ok(img) => {
                if img.width > 0
                    && img.height > 0
                    && img.rgba.len() == (img.width as usize) * (img.height as usize) * 4
                {
                    ok += 1;
                } else {
                    failures.push((path, ResvgError::InvalidSize));
                }
            }
            Err(e) => failures.push((path, e)),
        }
    }

    eprintln!(
        "full suite: {} ok, {} failed (of {} SVGs)",
        ok,
        failures.len(),
        ok + failures.len()
    );
    for (path, err) in &failures {
        eprintln!("  FAIL {} ({err:?})", path.display());
    }

    // Allow a small number of edge-case failures; smoke covers strict regressions in CI.
    let fail_rate = failures.len() as f64 / (ok + failures.len()).max(1) as f64;
    assert!(
        fail_rate <= 0.02,
        "full suite failure rate {:.1}% exceeds 2% threshold",
        fail_rate * 100.0
    );
}

fn collect_svgs(dir: &Path, out: &mut Vec<PathBuf>) {
    let entries = std::fs::read_dir(dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display()));
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_svgs(&path, out);
        } else if path.extension().is_some_and(|ext| ext == "svg") {
            out.push(path);
        }
    }
}
