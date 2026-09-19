//! Generate suite golden JSONL: `path\\tsha256\\twidth\\theight` per SVG.
//!
//! ```text
//! cargo run -p resvg-mobile --bin suite-goldens -- --manifest smoke --out …/smoke.jsonl
//! cargo run -p resvg-mobile --bin suite-goldens -- --manifest full --out …/full.jsonl
//! ```

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use uniffi_resvg_mobile::suite_contract::{format_result_line, suite_render_options};
use uniffi_resvg_mobile::render_file;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut manifest = "smoke".to_string();
    let mut out: Option<PathBuf> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--manifest" => {
                i += 1;
                manifest = args.get(i).cloned().unwrap_or_else(|| "smoke".into());
            }
            "--out" => {
                i += 1;
                out = args.get(i).map(PathBuf::from);
            }
            "-h" | "--help" => {
                eprintln!(
                    "Usage: suite-goldens --manifest smoke|full --out <file.jsonl>\n\
                     Optional: --dump-dir <dir> writes path.rgba dumps for fuzzy compare"
                );
                return ExitCode::SUCCESS;
            }
            "--dump-dir" => {
                i += 1;
                // Handled below via env for simplicity in scripts.
                if let Some(dir) = args.get(i) {
                    std::env::set_var("SUITE_DUMP_DIR", dir);
                }
            }
            other => {
                eprintln!("unknown arg: {other}");
                return ExitCode::FAILURE;
            }
        }
        i += 1;
    }
    let Some(out_path) = out else {
        eprintln!("--out is required");
        return ExitCode::FAILURE;
    };

    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let suite_root = manifest_dir.join("tests/suite/vendor/resvg-test-suite/tests");
    if !suite_root.is_dir() {
        eprintln!(
            "suite not found at {} — run ./scripts/fetch-test-suite.sh",
            suite_root.display()
        );
        return ExitCode::FAILURE;
    }

    let rel_paths: Vec<String> = match manifest.as_str() {
        "smoke" => load_manifest(&manifest_dir.join("tests/suite/smoke.txt")),
        "full" => {
            let mut paths = Vec::new();
            collect_svgs(&suite_root, &suite_root, &mut paths);
            paths.sort();
            paths
        }
        other => {
            eprintln!("unknown manifest: {other} (smoke|full)");
            return ExitCode::FAILURE;
        }
    };

    // Smoke is font-free; full suite loads vendor fonts/ when present (text cases).
    let font_dirs: Vec<String> = if manifest == "full" {
        suite_root
            .parent()
            .map(|p| p.join("fonts"))
            .filter(|p| p.is_dir())
            .map(|p| vec![p.to_string_lossy().into_owned()])
            .unwrap_or_default()
    } else {
        Vec::new()
    };

    let options = suite_render_options();
    let dump_dir = std::env::var_os("SUITE_DUMP_DIR").map(PathBuf::from);

    let mut lines = BTreeMap::new();
    let mut failures = 0usize;
    for rel in &rel_paths {
        let path = suite_root.join(rel);
        if !path.is_file() {
            eprintln!("MISSING {rel}");
            failures += 1;
            continue;
        }
        match render_file(&path, options.clone(), font_dirs.clone()) {
            Ok(img) => {
                if let Some(ref dump) = dump_dir {
                    let out_rgba = dump.join(format!("{rel}.rgba"));
                    if let Some(parent) = out_rgba.parent() {
                        let _ = fs::create_dir_all(parent);
                    }
                    let _ = fs::write(&out_rgba, &img.rgba);
                    let meta = dump.join(format!("{rel}.meta"));
                    let _ = fs::write(&meta, format!("{} {}\n", img.width, img.height));
                }
                lines.insert(rel.clone(), format_result_line(rel, &img));
            }
            Err(e) => {
                eprintln!("FAIL {rel}: {e:?}");
                failures += 1;
            }
        }
    }

    if let Some(parent) = out_path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let body: String = lines.values().cloned().map(|l| l + "\n").collect();
    if let Err(e) = fs::write(&out_path, body) {
        eprintln!("write {}: {e}", out_path.display());
        return ExitCode::FAILURE;
    }
    eprintln!(
        "Wrote {} entries to {} ({} failures)",
        lines.len(),
        out_path.display(),
        failures
    );
    let total = lines.len() + failures;
    let fail_rate = if total == 0 {
        1.0
    } else {
        failures as f64 / total as f64
    };
    // Smoke: zero failures. Full: same ≤2% gate as svg_suite::full_suite_renders.
    let max_fail = if manifest == "full" { 0.02 } else { 0.0 };
    if fail_rate > max_fail {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

fn load_manifest(path: &Path) -> Vec<String> {
    fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(str::to_string)
        .collect()
}

fn collect_svgs(root: &Path, dir: &Path, out: &mut Vec<String>) {
    let entries = fs::read_dir(dir).unwrap_or_else(|e| panic!("read_dir {}: {e}", dir.display()));
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_svgs(root, &path, out);
        } else if path.extension().is_some_and(|e| e == "svg") {
            let rel = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            out.push(rel);
        }
    }
}
