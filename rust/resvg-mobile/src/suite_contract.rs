//! Shared contract for cross-platform SVG suite goldens (Rust / Android / iOS).

use sha2::{Digest, Sha256};

use crate::{FitMode, RenderOptions, RenderedImage, Rgba};

/// Output box used by smoke/full suite goldens on all platforms.
pub const SUITE_RENDER_SIDE: u32 = 512;

/// Render options that every platform harness must use for suite hashing.
pub fn suite_render_options() -> RenderOptions {
    RenderOptions {
        width: Some(SUITE_RENDER_SIDE),
        height: Some(SUITE_RENDER_SIDE),
        fit: FitMode::Contain,
        background: Some(Rgba {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        }),
    }
}

/// SHA-256 hex digest of straight RGBA bytes (lowercase).
pub fn rgba_sha256(rgba: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(rgba);
    format!("{:x}", hasher.finalize())
}

/// One golden / result line: `path\tsha256\twidth\theight`
pub fn format_result_line(rel_path: &str, img: &RenderedImage) -> String {
    format!(
        "{}\t{}\t{}\t{}",
        rel_path,
        rgba_sha256(&img.rgba),
        img.width,
        img.height
    )
}

/// Parse a JSONL/TSV result line into (path, sha256, width, height).
pub fn parse_result_line(line: &str) -> Option<(String, String, u32, u32)> {
    let mut parts = line.split('\t');
    let path = parts.next()?.to_string();
    let sha = parts.next()?.to_string();
    let w: u32 = parts.next()?.parse().ok()?;
    let h: u32 = parts.next()?.parse().ok()?;
    Some((path, sha, w, h))
}
