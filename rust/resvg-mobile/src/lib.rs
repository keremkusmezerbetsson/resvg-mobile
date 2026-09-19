//! Cross-platform SVG rasterizer powered by resvg/usvg.
//!
//! Pixel format: **straight (non-premultiplied) RGBA**, row-major.
//! Callers should convert on the platform side (`UIImage` / `Bitmap`).

use std::path::{Path, PathBuf};

use tiny_skia::{Pixmap, Transform};
use usvg::{Options as UsvgOptions, Tree};

uniffi::include_scaffolding!("resvg_mobile");

pub mod suite_contract;

/// Hard cap on either output dimension.
pub const MAX_DIMENSION: u32 = 8192;

/// Hard cap on total output pixels (`width * height`) to bound peak memory.
/// At 4 bytes/pixel this is ~16 MiB for the pixmap alone.
pub const MAX_PIXELS: u32 = 4_194_304; // 2048²

/// How to map the SVG into the requested pixel box.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FitMode {
    /// Letterbox inside width×height, preserving aspect ratio.
    Contain,
    /// Cover width×height, preserving aspect ratio (may crop).
    Cover,
    /// Stretch to exact width×height.
    Fill,
    /// Use SVG intrinsic size when neither axis is set; if exactly one axis is
    /// set, derive the other while preserving aspect ratio. When both axes are
    /// set they are ignored (same as neither).
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

/// Map an SVG `font-family` name to a face actually present in the font set.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FontAlias {
    pub requested: String,
    pub replacement: String,
}

/// Fonts to load for a render: directories, raw TTF/OTF/TTC bytes, and aliases.
#[derive(Debug, Clone, Default)]
pub struct FontConfig {
    pub dirs: Vec<String>,
    pub data: Vec<Vec<u8>>,
    pub aliases: Vec<FontAlias>,
    pub default_family: Option<String>,
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

#[cfg(feature = "text")]
mod text_fonts {
    use std::collections::hash_map::DefaultHasher;
    use std::collections::HashMap;
    use std::hash::{Hash, Hasher};
    use std::path::Path;
    use std::sync::{Arc, Mutex, OnceLock};

    use usvg::fontdb::{self, Database as FontDatabase};
    use usvg::{
        FontFamily, FontResolver, FontStretch, FontStyle, Options as UsvgOptions,
    };

    use super::{FontAlias, FontConfig};

    #[derive(Clone, PartialEq, Eq, Hash)]
    struct FontDbKey {
        dirs: Vec<String>,
        data_hashes: Vec<u64>,
    }

    fn font_db_cache() -> &'static Mutex<HashMap<FontDbKey, Arc<FontDatabase>>> {
        static CACHE: OnceLock<Mutex<HashMap<FontDbKey, Arc<FontDatabase>>>> = OnceLock::new();
        CACHE.get_or_init(|| Mutex::new(HashMap::new()))
    }

    fn hash_bytes(data: &[u8]) -> u64 {
        let mut hasher = DefaultHasher::new();
        data.hash(&mut hasher);
        hasher.finish()
    }

    fn font_db_key(fonts: &FontConfig) -> FontDbKey {
        let mut dirs: Vec<String> = fonts
            .dirs
            .iter()
            .filter(|dir| Path::new(dir.as_str()).is_dir())
            .cloned()
            .collect();
        dirs.sort();
        dirs.dedup();
        let data_hashes = fonts.data.iter().map(|blob| hash_bytes(blob)).collect();
        FontDbKey { dirs, data_hashes }
    }

    fn configure_generic_families(db: &mut FontDatabase) {
        // Match resvg-test-suite fonts when present; names are stored even if missing.
        db.set_sans_serif_family("Noto Sans");
        db.set_serif_family("Noto Serif");
        db.set_monospace_family("Noto Mono");
        db.set_cursive_family("Yellowtail");
        db.set_fantasy_family("Sedgwick Ave Display");
    }

    fn normalize_family(name: &str) -> String {
        name.split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
            .to_ascii_lowercase()
    }

    fn alias_map(aliases: &[FontAlias]) -> HashMap<String, String> {
        let mut map = HashMap::new();
        for alias in aliases {
            let from = normalize_family(&alias.requested);
            let to = alias.replacement.trim();
            if !from.is_empty() && !to.is_empty() {
                map.insert(from, to.to_string());
            }
        }
        map
    }

    fn stretch_to_fontdb(stretch: FontStretch) -> fontdb::Stretch {
        match stretch {
            FontStretch::UltraCondensed => fontdb::Stretch::UltraCondensed,
            FontStretch::ExtraCondensed => fontdb::Stretch::ExtraCondensed,
            FontStretch::Condensed => fontdb::Stretch::Condensed,
            FontStretch::SemiCondensed => fontdb::Stretch::SemiCondensed,
            FontStretch::Normal => fontdb::Stretch::Normal,
            FontStretch::SemiExpanded => fontdb::Stretch::SemiExpanded,
            FontStretch::Expanded => fontdb::Stretch::Expanded,
            FontStretch::ExtraExpanded => fontdb::Stretch::ExtraExpanded,
            FontStretch::UltraExpanded => fontdb::Stretch::UltraExpanded,
        }
    }

    fn style_to_fontdb(style: FontStyle) -> fontdb::Style {
        match style {
            FontStyle::Normal => fontdb::Style::Normal,
            FontStyle::Italic => fontdb::Style::Italic,
            FontStyle::Oblique => fontdb::Style::Oblique,
        }
    }

    fn aliased_font_selector(
        aliases: Arc<HashMap<String, String>>,
    ) -> usvg::FontSelectionFn<'static> {
        Box::new(move |font, db| {
            let mut named: Vec<String> = Vec::new();
            let mut generics: Vec<fontdb::Family<'_>> = Vec::new();

            for family in font.families() {
                match family {
                    FontFamily::Named(name) => {
                        if let Some(replacement) = aliases.get(&normalize_family(name)) {
                            named.push(replacement.clone());
                        }
                        named.push(name.clone());
                    }
                    FontFamily::Serif => {
                        if let Some(replacement) = aliases.get("serif") {
                            named.push(replacement.clone());
                        }
                        generics.push(fontdb::Family::Serif);
                    }
                    FontFamily::SansSerif => {
                        if let Some(replacement) = aliases.get("sans-serif") {
                            named.push(replacement.clone());
                        }
                        generics.push(fontdb::Family::SansSerif);
                    }
                    FontFamily::Cursive => {
                        if let Some(replacement) = aliases.get("cursive") {
                            named.push(replacement.clone());
                        }
                        generics.push(fontdb::Family::Cursive);
                    }
                    FontFamily::Fantasy => {
                        if let Some(replacement) = aliases.get("fantasy") {
                            named.push(replacement.clone());
                        }
                        generics.push(fontdb::Family::Fantasy);
                    }
                    FontFamily::Monospace => {
                        if let Some(replacement) = aliases.get("monospace") {
                            named.push(replacement.clone());
                        }
                        generics.push(fontdb::Family::Monospace);
                    }
                }
            }

            let mut families: Vec<fontdb::Family<'_>> = named
                .iter()
                .map(|name| fontdb::Family::Name(name.as_str()))
                .collect();
            families.extend(generics);
            families.push(fontdb::Family::Serif);

            let query = fontdb::Query {
                families: &families,
                weight: fontdb::Weight(font.weight()),
                stretch: stretch_to_fontdb(font.stretch()),
                style: style_to_fontdb(font.style()),
            };
            db.query(&query)
        })
    }

    fn load_font_database(fonts: &FontConfig) -> Arc<FontDatabase> {
        let key = font_db_key(fonts);
        {
            let cache = font_db_cache().lock().unwrap_or_else(|e| e.into_inner());
            if let Some(existing) = cache.get(&key) {
                return existing.clone();
            }
        }

        let mut db = FontDatabase::new();
        for dir in &key.dirs {
            db.load_fonts_dir(Path::new(dir));
        }
        for blob in &fonts.data {
            db.load_font_data(blob.clone());
        }
        configure_generic_families(&mut db);
        let loaded = Arc::new(db);

        let mut cache = font_db_cache().lock().unwrap_or_else(|e| e.into_inner());
        cache.entry(key).or_insert_with(|| loaded.clone()).clone()
    }

    fn key_has_faces(key: &FontDbKey) -> bool {
        !key.dirs.is_empty() || !key.data_hashes.is_empty()
    }

    pub(super) fn usvg_options(fonts: &FontConfig) -> UsvgOptions<'static> {
        let mut opt = UsvgOptions::default();
        opt.fontdb = load_font_database(fonts);
        if let Some(family) = fonts
            .default_family
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            opt.font_family = family.to_string();
        } else if key_has_faces(&font_db_key(fonts)) {
            opt.font_family = "Noto Sans".into();
        }

        if !fonts.aliases.is_empty() {
            opt.font_resolver = FontResolver {
                select_font: aliased_font_selector(Arc::new(alias_map(&fonts.aliases))),
                select_fallback: FontResolver::default_fallback_selector(),
            };
        }
        opt
    }
}

#[cfg(feature = "text")]
fn usvg_options(fonts: &FontConfig) -> UsvgOptions<'static> {
    text_fonts::usvg_options(fonts)
}

#[cfg(not(feature = "text"))]
fn usvg_options(_fonts: &FontConfig) -> UsvgOptions<'static> {
    // FontConfig is ignored when the text stack is compiled out.
    UsvgOptions::default()
}

fn parse_tree(
    svg: &[u8],
    fonts: &FontConfig,
    resources_dir: Option<PathBuf>,
) -> Result<Tree, ResvgError> {
    let mut opt = usvg_options(fonts);
    opt.resources_dir = resources_dir;
    Tree::from_data(svg, &opt).map_err(|_| ResvgError::Parse)
}

/// Intrinsic SVG size in user units (CSS pixels).
pub fn intrinsic_size(svg: &[u8]) -> Result<SizeF, ResvgError> {
    let tree = parse_tree(svg, &FontConfig::default(), None)?;
    let size = tree.size();
    Ok(SizeF {
        width: size.width(),
        height: size.height(),
    })
}

pub fn render(svg: &[u8], options: RenderOptions) -> Result<RenderedImage, ResvgError> {
    render_with_font_config(svg, options, FontConfig::default())
}

pub fn render_with_fonts(
    svg: &[u8],
    options: RenderOptions,
    font_dirs: Vec<String>,
) -> Result<RenderedImage, ResvgError> {
    render_with_font_config(
        svg,
        options,
        FontConfig {
            dirs: font_dirs,
            ..FontConfig::default()
        },
    )
}

pub fn render_with_font_config(
    svg: &[u8],
    options: RenderOptions,
    fonts: FontConfig,
) -> Result<RenderedImage, ResvgError> {
    render_with_resources(svg, options, fonts, None)
}

/// Render SVG bytes, resolving relative image hrefs from `resources_dir` when set
/// (same role as the SVG parent directory in [`render_file`]).
pub fn render_with_resources(
    svg: &[u8],
    options: RenderOptions,
    fonts: FontConfig,
    resources_dir: Option<String>,
) -> Result<RenderedImage, ResvgError> {
    let resources_dir = resources_dir.map(PathBuf::from);
    let tree = parse_tree(svg, &fonts, resources_dir)?;
    render_tree(&tree, options)
}

/// Render an SVG file, resolving relative resources (images, fonts) from its parent directory.
pub fn render_file(
    path: &Path,
    options: RenderOptions,
    font_dirs: Vec<String>,
) -> Result<RenderedImage, ResvgError> {
    let svg = std::fs::read(path).map_err(|_| ResvgError::Parse)?;
    let resources_dir = path.parent().map(|p| p.to_string_lossy().into_owned());
    let fonts = FontConfig {
        dirs: font_dirs,
        ..FontConfig::default()
    };
    render_with_resources(&svg, options, fonts, resources_dir)
}

/// Intrinsic size of an SVG file (with relative resource resolution from its parent directory).
pub fn intrinsic_size_file(path: &Path) -> Result<SizeF, ResvgError> {
    let svg = std::fs::read(path).map_err(|_| ResvgError::Parse)?;
    let resources_dir = path.parent().map(|p| p.to_path_buf());
    let tree = parse_tree(&svg, &FontConfig::default(), resources_dir)?;
    let size = tree.size();
    Ok(SizeF {
        width: size.width(),
        height: size.height(),
    })
}

fn render_tree(tree: &Tree, options: RenderOptions) -> Result<RenderedImage, ResvgError> {
    let (out_w, out_h, transform) = compute_layout(tree, &options)?;

    let mut pixmap = Pixmap::new(out_w, out_h).ok_or(ResvgError::InvalidSize)?;

    if let Some(bg) = options.background {
        let color = tiny_skia::Color::from_rgba8(bg.r, bg.g, bg.b, bg.a);
        pixmap.fill(color);
    }

    resvg::render(tree, transform, &mut pixmap.as_mut());

    // tiny-skia stores premultiplied RGBA; convert to straight for platform APIs.
    let rgba = premultiplied_to_straight(pixmap.data());

    Ok(RenderedImage {
        width: out_w,
        height: out_h,
        rgba,
    })
}

fn check_size(out_w: u32, out_h: u32) -> Result<(), ResvgError> {
    if out_w == 0 || out_h == 0 || out_w > MAX_DIMENSION || out_h > MAX_DIMENSION {
        return Err(ResvgError::InvalidSize);
    }
    let pixels = (out_w as u64).saturating_mul(out_h as u64);
    if pixels > MAX_PIXELS as u64 {
        return Err(ResvgError::InvalidSize);
    }
    Ok(())
}

fn compute_layout(
    tree: &Tree,
    options: &RenderOptions,
) -> Result<(u32, u32, Transform), ResvgError> {
    let svg_w = tree.size().width().max(1.0);
    let svg_h = tree.size().height().max(1.0);

    let (out_w, out_h) = match options.fit {
        FitMode::Intrinsic => match (options.width, options.height) {
            (None, None) | (Some(_), Some(_)) => {
                // Both set → ignore and use intrinsic (matches API contract).
                (svg_w.ceil() as u32, svg_h.ceil() as u32)
            }
            (Some(w), None) => {
                let w = w.max(1);
                let h = ((svg_h / svg_w) * w as f32).ceil() as u32;
                (w, h.max(1))
            }
            (None, Some(h)) => {
                let h = h.max(1);
                let w = ((svg_w / svg_h) * h as f32).ceil() as u32;
                (w.max(1), h)
            }
        },
        FitMode::Contain | FitMode::Cover | FitMode::Fill => {
            let w = options.width.ok_or(ResvgError::InvalidSize)?.max(1);
            let h = options.height.ok_or(ResvgError::InvalidSize)?.max(1);
            (w, h)
        }
    };

    check_size(out_w, out_h)?;

    let transform = match options.fit {
        FitMode::Fill => {
            let sx = out_w as f32 / svg_w;
            let sy = out_h as f32 / svg_h;
            Transform::from_scale(sx, sy)
        }
        FitMode::Intrinsic => {
            let sx = out_w as f32 / svg_w;
            let sy = out_h as f32 / svg_h;
            // Axes are aspect-preserving except when both were ignored → 1:1 scale.
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
    fn render_default_intrinsic_works() {
        let img = render(CIRCLE_SVG, RenderOptions::default()).unwrap();
        assert_eq!(img.width, 100);
        assert_eq!(img.height, 100);
    }

    #[test]
    fn intrinsic_ignores_both_axes() {
        let img = render(
            CIRCLE_SVG,
            RenderOptions {
                width: Some(50),
                height: Some(200),
                fit: FitMode::Intrinsic,
                background: None,
            },
        )
        .unwrap();
        assert_eq!(img.width, 100);
        assert_eq!(img.height, 100);
    }

    #[test]
    fn intrinsic_one_axis_preserves_aspect() {
        let img = render(
            CIRCLE_SVG,
            RenderOptions {
                width: Some(50),
                height: None,
                fit: FitMode::Intrinsic,
                background: None,
            },
        )
        .unwrap();
        assert_eq!(img.width, 50);
        assert_eq!(img.height, 50);
    }

    #[test]
    fn contain_requires_both_dimensions() {
        let err = render(
            CIRCLE_SVG,
            RenderOptions {
                width: None,
                height: None,
                fit: FitMode::Contain,
                background: None,
            },
        )
        .unwrap_err();
        assert_eq!(err, ResvgError::InvalidSize);
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
    fn rejects_oversized_edge() {
        let err = render(
            CIRCLE_SVG,
            RenderOptions {
                width: Some(MAX_DIMENSION + 1),
                height: Some(64),
                fit: FitMode::Fill,
                background: None,
            },
        )
        .unwrap_err();
        assert_eq!(err, ResvgError::InvalidSize);
    }

    #[test]
    fn rejects_oversized_area() {
        // Within edge cap but over pixel budget.
        let side = ((MAX_PIXELS as f64).sqrt().floor() as u32) + 1;
        assert!(side <= MAX_DIMENSION);
        let err = render(
            CIRCLE_SVG,
            RenderOptions {
                width: Some(side),
                height: Some(side),
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

    fn opaque_pixel_count(img: &RenderedImage) -> usize {
        img.rgba.chunks_exact(4).filter(|px| px[3] > 0).count()
    }

    #[test]
    fn text_is_skipped_without_fonts() {
        let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="80">
            <text x="8" y="52" font-family="Noto Sans" font-size="36" fill="#111">Hello</text>
        </svg>"##;
        let img = render(
            svg,
            RenderOptions {
                width: Some(200),
                height: Some(80),
                fit: FitMode::Fill,
                background: None,
            },
        )
        .unwrap();
        assert_eq!(
            opaque_pixel_count(&img),
            0,
            "text must not paint without a matching font"
        );
    }

    #[cfg(feature = "text")]
    #[test]
    fn text_renders_with_suite_fonts() {
        let fonts = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/suite/vendor/resvg-test-suite/fonts");
        if !fonts.is_dir() {
            eprintln!("skipping text_renders_with_suite_fonts — run ./scripts/fetch-test-suite.sh");
            return;
        }

        let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="80">
            <text x="8" y="52" font-family="Noto Sans" font-size="36" fill="#111">Hello</text>
        </svg>"##;
        let img = render_with_fonts(
            svg,
            RenderOptions {
                width: Some(200),
                height: Some(80),
                fit: FitMode::Fill,
                background: None,
            },
            vec![fonts.to_string_lossy().into_owned()],
        )
        .unwrap();
        assert!(
            opaque_pixel_count(&img) > 200,
            "expected painted glyphs after loading suite fonts, got {}",
            opaque_pixel_count(&img)
        );
    }

    #[cfg(feature = "text")]
    fn suite_noto_regular() -> Option<Vec<u8>> {
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/suite/vendor/resvg-test-suite/fonts/NotoSans-Regular.ttf");
        std::fs::read(path).ok()
    }

    #[cfg(feature = "text")]
    #[test]
    fn text_renders_from_raw_font_bytes() {
        let Some(font) = suite_noto_regular() else {
            eprintln!("skipping text_renders_from_raw_font_bytes — run ./scripts/fetch-test-suite.sh");
            return;
        };
        let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="80">
            <text x="8" y="52" font-family="Noto Sans" font-size="36" fill="#111">Hello</text>
        </svg>"##;
        let img = render_with_font_config(
            svg,
            RenderOptions {
                width: Some(200),
                height: Some(80),
                fit: FitMode::Fill,
                background: None,
            },
            FontConfig {
                data: vec![font],
                ..FontConfig::default()
            },
        )
        .unwrap();
        assert!(
            opaque_pixel_count(&img) > 200,
            "expected painted glyphs from raw font bytes, got {}",
            opaque_pixel_count(&img)
        );
    }

    #[cfg(feature = "text")]
    #[test]
    fn font_alias_maps_missing_family() {
        let Some(font) = suite_noto_regular() else {
            eprintln!("skipping font_alias_maps_missing_family — run ./scripts/fetch-test-suite.sh");
            return;
        };
        let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="80">
            <text x="8" y="52" font-family="App Sans" font-size="36" fill="#111">Hello</text>
        </svg>"##;
        let without_alias = render_with_font_config(
            svg,
            RenderOptions {
                width: Some(200),
                height: Some(80),
                fit: FitMode::Fill,
                background: None,
            },
            FontConfig {
                data: vec![font.clone()],
                ..FontConfig::default()
            },
        )
        .unwrap();
        let with_alias = render_with_font_config(
            svg,
            RenderOptions {
                width: Some(200),
                height: Some(80),
                fit: FitMode::Fill,
                background: None,
            },
            FontConfig {
                data: vec![font],
                aliases: vec![FontAlias {
                    requested: "App Sans".into(),
                    replacement: "Noto Sans".into(),
                }],
                ..FontConfig::default()
            },
        )
        .unwrap();
        assert_eq!(opaque_pixel_count(&without_alias), 0);
        assert!(
            opaque_pixel_count(&with_alias) > 200,
            "alias should resolve App Sans to Noto Sans, got {}",
            opaque_pixel_count(&with_alias)
        );
    }

    #[cfg(not(feature = "text"))]
    #[test]
    fn render_works_without_text_feature() {
        let img = render(CIRCLE_SVG, RenderOptions::default()).unwrap();
        assert_eq!(img.width, 100);
        assert_eq!(img.height, 100);
        assert!(!img.rgba.is_empty());
    }
}
