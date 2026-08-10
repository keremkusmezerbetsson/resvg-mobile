//! Cross-platform SVG rasterizer powered by resvg/usvg.
//!
//! Pixel format: **straight (non-premultiplied) RGBA**, row-major.
//! Callers should convert on the platform side (`UIImage` / `Bitmap`).

use std::path::PathBuf;

use tiny_skia::{Pixmap, Transform};
use usvg::{Options as UsvgOptions, Tree};

uniffi::include_scaffolding!("resvg_mobile");

/// Hard cap on either output dimension to avoid OOM on pathological SVGs.
pub const MAX_DIMENSION: u32 = 8192;

/// How to map the SVG into the requested pixel box.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FitMode {
    /// Letterbox inside width×height, preserving aspect ratio.
    Contain,
    /// Cover width×height, preserving aspect ratio (may crop).
    Cover,
    /// Stretch to exact width×height.
    Fill,
    /// Use SVG intrinsic size (ignore width/height unless one axis is set).
    Intrinsic,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rgba {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[derive(Debug, Clone)]
pub struct RenderOptions {
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub fit: FitMode,
    pub background: Option<Rgba>,
}

impl Default for RenderOptions {
    fn default() -> Self {
        Self {
            width: None,
            height: None,
            fit: FitMode::Intrinsic,
            background: None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct RenderedImage {
    pub width: u32,
    pub height: u32,
    /// Straight (non-premultiplied) RGBA.
    pub rgba: Vec<u8>,
}

#[derive(Debug, Clone, Copy)]
pub struct SizeF {
    pub width: f32,
    pub height: f32,
}

#[derive(Debug, thiserror::Error, Clone, PartialEq, Eq)]
pub enum ResvgError {
    #[error("failed to parse SVG")]
    Parse,
    #[error("failed to render SVG")]
    Render,
    #[error("invalid output size")]
    InvalidSize,
    #[error("failed to load fonts")]
    Fonts,
}

fn usvg_options(font_dirs: &[String]) -> UsvgOptions<'static> {
    let mut opt = UsvgOptions::default();
    for dir in font_dirs {
        let path = PathBuf::from(dir);
        if path.is_dir() {
            opt.fontdb_mut().load_fonts_dir(&path);
        }
    }
    opt
}

fn parse_tree(svg: &[u8], font_dirs: &[String]) -> Result<Tree, ResvgError> {
    let opt = usvg_options(font_dirs);
    Tree::from_data(svg, &opt).map_err(|_| ResvgError::Parse)
}

/// Intrinsic SVG size in user units (CSS pixels).
pub fn intrinsic_size(svg: &[u8]) -> Result<SizeF, ResvgError> {
    let tree = parse_tree(svg, &[])?;
    let size = tree.size();
    Ok(SizeF {
        width: size.width(),
        height: size.height(),
    })
}

pub fn render(svg: &[u8], options: RenderOptions) -> Result<RenderedImage, ResvgError> {
    render_with_fonts(svg, options, Vec::new())
}

pub fn render_with_fonts(
    svg: &[u8],
    options: RenderOptions,
    font_dirs: Vec<String>,
) -> Result<RenderedImage, ResvgError> {
    let tree = parse_tree(svg, &font_dirs)?;
    let (out_w, out_h, transform) = compute_layout(&tree, &options)?;

    let mut pixmap = Pixmap::new(out_w, out_h).ok_or(ResvgError::InvalidSize)?;

    if let Some(bg) = options.background {
        let color = tiny_skia::Color::from_rgba8(bg.r, bg.g, bg.b, bg.a);
        pixmap.fill(color);
    }

    resvg::render(&tree, transform, &mut pixmap.as_mut());

    // tiny-skia stores premultiplied RGBA; convert to straight for platform APIs.
    let rgba = premultiplied_to_straight(pixmap.data());

    Ok(RenderedImage {
        width: out_w,
        height: out_h,
        rgba,
    })
}

fn compute_layout(
    tree: &Tree,
    options: &RenderOptions,
) -> Result<(u32, u32, Transform), ResvgError> {
    let svg_w = tree.size().width().max(1.0);
    let svg_h = tree.size().height().max(1.0);

    let (out_w, out_h) = match options.fit {
        FitMode::Intrinsic => {
            if options.width.is_none() && options.height.is_some() {
                let h = options.height.unwrap().max(1);
                let w = ((svg_w / svg_h) * h as f32).ceil() as u32;
                (w.max(1), h)
            } else {
                let w = options.width.unwrap_or(svg_w.ceil() as u32).max(1);
                let h = options
                    .height
                    .unwrap_or_else(|| ((svg_h / svg_w) * w as f32).ceil() as u32)
                    .max(1);
                (w, h)
            }
        }
        FitMode::Contain | FitMode::Cover | FitMode::Fill => {
            let w = options.width.ok_or(ResvgError::InvalidSize)?.max(1);
            let h = options.height.ok_or(ResvgError::InvalidSize)?.max(1);
            (w, h)
        }
    };

    if out_w > MAX_DIMENSION || out_h > MAX_DIMENSION {
        return Err(ResvgError::InvalidSize);
    }

    let transform = match options.fit {
        FitMode::Fill | FitMode::Intrinsic => {
            let sx = out_w as f32 / svg_w;
            let sy = out_h as f32 / svg_h;
            Transform::from_scale(sx, sy)
        }
        FitMode::Contain => {
            let scale = (out_w as f32 / svg_w).min(out_h as f32 / svg_h);
            let dx = (out_w as f32 - svg_w * scale) * 0.5;
            let dy = (out_h as f32 - svg_h * scale) * 0.5;
            Transform::from_row(scale, 0.0, 0.0, scale, dx, dy)
        }
        FitMode::Cover => {
            let scale = (out_w as f32 / svg_w).max(out_h as f32 / svg_h);
            let dx = (out_w as f32 - svg_w * scale) * 0.5;
            let dy = (out_h as f32 - svg_h * scale) * 0.5;
            Transform::from_row(scale, 0.0, 0.0, scale, dx, dy)
        }
    };

    Ok((out_w, out_h, transform))
}

fn premultiplied_to_straight(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len());
    for chunk in data.chunks_exact(4) {
        let (r, g, b, a) = (chunk[0], chunk[1], chunk[2], chunk[3]);
        if a == 0 {
            out.extend_from_slice(&[0, 0, 0, 0]);
        } else if a == 255 {
            out.extend_from_slice(&[r, g, b, a]);
        } else {
            let af = a as f32;
            out.push(((r as f32 * 255.0) / af).round().min(255.0) as u8);
            out.push(((g as f32 * 255.0) / af).round().min(255.0) as u8);
            out.push(((b as f32 * 255.0) / af).round().min(255.0) as u8);
            out.push(a);
        }
    }
    out
}

/// Default system font directories used by platform helpers.
pub fn default_font_dirs() -> Vec<String> {
    #[cfg(target_os = "ios")]
    {
        vec![
            "/System/Library/Fonts".into(),
            "/System/Library/Fonts/Core".into(),
        ]
    }
    #[cfg(target_os = "android")]
    {
        vec!["/system/fonts".into()]
    }
    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    {
        let mut dirs = Vec::new();
        if cfg!(target_os = "macos") {
            dirs.push("/System/Library/Fonts".into());
            dirs.push("/Library/Fonts".into());
        } else if cfg!(target_os = "linux") {
            dirs.push("/usr/share/fonts".into());
            dirs.push("/usr/local/share/fonts".into());
        }
        dirs
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    const CIRCLE_SVG: &[u8] = br##"
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
          <circle cx="50" cy="50" r="40" fill="#3366ff"/>
        </svg>
    "##;

    #[test]
    fn intrinsic_size_works() {
        let size = intrinsic_size(CIRCLE_SVG).unwrap();
        assert!((size.width - 100.0).abs() < 0.01);
        assert!((size.height - 100.0).abs() < 0.01);
    }

    #[test]
    fn render_contain_produces_pixels() {
        let img = render(
            CIRCLE_SVG,
            RenderOptions {
                width: Some(64),
                height: Some(64),
                fit: FitMode::Contain,
                background: Some(Rgba {
                    r: 255,
                    g: 255,
                    b: 255,
                    a: 255,
                }),
            },
        )
        .unwrap();
        assert_eq!(img.width, 64);
        assert_eq!(img.height, 64);
        assert_eq!(img.rgba.len(), 64 * 64 * 4);
        let mid = ((32 * 64 + 32) * 4) as usize;
        assert!(img.rgba[mid + 2] > 100, "expected blue channel");
    }

    #[test]
    fn rejects_oversized() {
        let err = render(
            CIRCLE_SVG,
            RenderOptions {
                width: Some(MAX_DIMENSION + 1),
                height: Some(MAX_DIMENSION + 1),
                fit: FitMode::Fill,
                background: None,
            },
        )
        .unwrap_err();
        assert_eq!(err, ResvgError::InvalidSize);
    }

    #[test]
    fn parse_error_on_garbage() {
        let err = render(b"not svg", RenderOptions::default()).unwrap_err();
        assert_eq!(err, ResvgError::Parse);
    }

    #[test]
    fn golden_hash_stable() {
        let img = render(
            CIRCLE_SVG,
            RenderOptions {
                width: Some(32),
                height: Some(32),
                fit: FitMode::Fill,
                background: Some(Rgba {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 0,
                }),
            },
        )
        .unwrap();
        let mut hasher = Sha256::new();
        hasher.update(&img.rgba);
        let digest = format!("{:x}", hasher.finalize());
        assert_eq!(digest.len(), 64);
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/circle_32_fill.sha256");
        let expected = std::fs::read_to_string(path).unwrap_or_default().trim().to_string();
        if expected.is_empty() {
            std::fs::create_dir_all(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures")).ok();
            std::fs::write(path, &digest).unwrap();
        } else {
            assert_eq!(digest, expected, "golden pixel hash changed");
        }
    }
}
