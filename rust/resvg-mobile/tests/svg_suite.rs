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

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use uniffi_resvg_mobile::suite_contract::{
    format_result_line, parse_result_line, rgba_sha256, suite_render_options,
};
use uniffi_resvg_mobile::{render_file, ResvgError, MAX_DIMENSION, MAX_PIXELS};

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

fn load_goldens(name: &str) -> HashMap<String, (String, u32, u32)> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/suite/goldens")
        .join(name);
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| {
        panic!(
            "missing goldens at {} ({e}) — run ./scripts/generate-suite-goldens.sh",
            path.display()
        )
    });
    let mut map = HashMap::new();
    for line in text.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with('#')) {
        let (path, sha, w, h) =
            parse_result_line(line).unwrap_or_else(|| panic!("bad golden line: {line}"));
        map.insert(path, (sha, w, h));
    }
    map
}

fn full_suite_font_dirs() -> Vec<String> {
    let fonts = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/suite/vendor/resvg-test-suite/fonts");
    if fonts.is_dir() {
        vec![fonts.to_string_lossy().into_owned()]
    } else {
        Vec::new()
    }
}

fn assert_renders_and_hash(
    path: &Path,
    rel: &str,
    expected: Option<&(String, u32, u32)>,
    font_dirs: Vec<String>,
) {
    let img = render_file(path, suite_render_options(), font_dirs).unwrap_or_else(|e| {
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

    if let Some((exp_sha, exp_w, exp_h)) = expected {
        let got = format_result_line(rel, &img);
        let (p, sha, w, h) = parse_result_line(&got).expect("format_result_line");
        assert_eq!(p, rel);
        assert_eq!(
            (&sha, w, h),
            (exp_sha, *exp_w, *exp_h),
            "golden mismatch for {rel}\n  got  {sha} {w}x{h}\n  want {exp_sha} {exp_w}x{exp_h}\n  digest={}",
            rgba_sha256(&img.rgba)
        );
    }
}

#[test]
fn smoke_suite_renders() {
    let root = require_suite();
    let rel_paths = load_manifest("smoke.txt");
    assert!(
        rel_paths.len() >= 55,
        "smoke manifest should list ~57 cases, got {}",
        rel_paths.len()
    );
    let goldens = load_goldens("smoke.jsonl");

    for rel in rel_paths {
        let path = root.join(&rel);
        assert!(path.is_file(), "missing smoke fixture: {}", path.display());
        let expected = goldens.get(&rel);
        assert!(
            expected.is_some(),
            "no golden for {rel} — regenerate smoke.jsonl"
        );
        // Smoke fixtures are font-free — empty FontConfig matches goldens / mobile harnesses.
        assert_renders_and_hash(&path, &rel, expected, Vec::new());
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

    let goldens_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/suite/goldens/full.jsonl");
    let goldens = if goldens_path.is_file() {
        Some(load_goldens("full.jsonl"))
    } else {
        eprintln!("no full.jsonl — render-only gate (generate with generate-suite-goldens.sh full)");
        None
    };

    let mut ok = 0usize;
    let mut failures: Vec<(PathBuf, ResvgError)> = Vec::new();
    let mut hash_mismatches = 0usize;

    for path in paths {
        let rel = path
            .strip_prefix(&root)
            .unwrap_or(&path)
            .to_string_lossy()
            .replace('\\', "/");
        match render_file(&path, suite_render_options(), full_suite_font_dirs()) {
            Ok(img) => {
                if img.width > 0
                    && img.height > 0
                    && img.rgba.len() == (img.width as usize) * (img.height as usize) * 4
                {
                    ok += 1;
                    if let Some(ref map) = goldens {
                        if let Some((exp_sha, exp_w, exp_h)) = map.get(&rel) {
                            let sha = rgba_sha256(&img.rgba);
                            if sha != *exp_sha || img.width != *exp_w || img.height != *exp_h {
                                hash_mismatches += 1;
                                eprintln!(
                                    "HASH {rel}: got {sha} {}x{} want {exp_sha} {exp_w}x{exp_h}",
                                    img.width, img.height
                                );
                            }
                        }
                    }
                } else {
                    failures.push((path, ResvgError::InvalidSize));
                }
            }
            Err(e) => failures.push((path, e)),
        }
    }

    eprintln!(
        "full suite: {} ok, {} failed, {} hash mismatches (of {} SVGs)",
        ok,
        failures.len(),
        hash_mismatches,
        ok + failures.len()
    );
    for (path, err) in &failures {
        eprintln!("  FAIL {} ({err:?})", path.display());
    }

    let fail_rate = failures.len() as f64 / (ok + failures.len()).max(1) as f64;
    assert!(
        fail_rate <= 0.02,
        "full suite failure rate {:.1}% exceeds 2% threshold",
        fail_rate * 100.0
    );
    if goldens.is_some() {
        assert_eq!(
            hash_mismatches, 0,
            "{hash_mismatches} full-suite hash mismatches vs full.jsonl"
        );
    }
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
