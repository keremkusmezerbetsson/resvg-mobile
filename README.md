# Resvg Mobile

[![CI](https://github.com/keremkusmezerbetsson/resvg-mobile/actions/workflows/ci.yml/badge.svg)](https://github.com/keremkusmezerbetsson/resvg-mobile/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Cross-platform SVG rasterizer for **Android** and **iOS**, built on
[resvg](https://github.com/linebender/resvg) with
[UniFFI](https://github.com/mozilla/uniffi-rs) bindings.

- Shared Rust core → identical pixels on both platforms
- Pixel format: **straight (non-premultiplied) RGBA**
- Platform adapters: `Bitmap` (Android) / `UIImage` (iOS)
- Optional UI: `ResvgImageView` + Compose / SwiftUI wrappers (LRU cache, off-main render)
- Optional Coil 3: `ResvgDecoder` (`:resvg-mobile-coil`) for `AsyncImage` / `ImageLoader`

## Layout

```
resvg-mobile/
  rust/resvg-mobile/   # Rust + UniFFI (cdylib / staticlib)
  ios/                 # Swift Package: ResvgMobile + ResvgMobileUI
  android/             # AARs: resvg-mobile, resvg-mobile-ui, resvg-mobile-coil + demo + gallery
  examples/            # Sample SVG, iOS demo, iOS gallery
  scripts/             # fetch-test-suite, sync-gallery-svgs, suite goldens/compare, ci-build
```

## Prerequisites

| Target | Tools |
|--------|--------|
| Rust | Rust stable (`rustup`), optionally `rustfmt` / `clippy` |
| Android | JDK 17, Android SDK + NDK, [`cargo-ndk`](https://github.com/bbqsrc/cargo-ndk), Rust Android targets |
| iOS | Xcode, Rust targets `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios` |

## Quick start

### Rust tests

```bash
(cd rust && cargo test -p resvg-mobile)

# Size-variant feature sets (CI also runs these):
(cd rust && cargo test -p resvg-mobile --no-default-features)
(cd rust && cargo test -p resvg-mobile --no-default-features --features text)
(cd rust && cargo test -p resvg-mobile --no-default-features --features images)
```

### iOS (Swift Package)

Native libraries are **not** committed (they are large). Build them first:

```bash
./rust/build-ios.sh   # full → ios/ResvgMobileFFI.xcframework + regenerates Swift
# VARIANT=minimal ./rust/build-ios.sh
# VARIANT=all ./rust/build-ios.sh   # also ios/variants/{full,no-images,no-text,minimal}/
open ios/Package.swift
```

See [ios/ResvgMobileFFI.BUILD.md](ios/ResvgMobileFFI.BUILD.md) for switching XCFramework variants.

```swift
import ResvgMobile

// Default fit is .intrinsic — works without width/height.
let image = try Resvg.renderUIImage(data: svgData)

// contain / cover / fill require both dimensions:
let sized = try Resvg.renderUIImage(
  data: svgData,
  options: RenderOptions(width: 128, height: 128, fit: .contain, background: nil),
  fonts: Resvg.bundledFontConfig()
)
```

Demo app: `examples/ios-demo/ResvgDemo.xcodeproj` (depends on the local SPM package after `build-ios.sh`).

### Gallery apps (visual regression)

Both gallery apps render the **8 custom SVGs** in `examples/svg-set/` plus the full
[linebender/resvg-test-suite](https://github.com/linebender/resvg-test-suite) corpus (~1,679 SVGs).

```bash
./scripts/fetch-test-suite.sh      # vendor suite for Rust tests + gallery sync
./scripts/sync-gallery-svgs.sh     # copy into android/gallery + ios-gallery bundles
```

| Platform | App |
|----------|-----|
| Android | `./gradlew :gallery:assembleDebug` (module `android/gallery`) |
| iOS | `examples/ios-gallery/ResvgGallery.xcodeproj` (after `build-ios.sh`) |

The synced `resvg-suite/` trees are gitignored (~21 MB); run `sync-gallery-svgs.sh` after cloning. Demo and gallery apps default to the **full** feature flavor.

### Android (AAR)

```bash
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

# Build native libs into src/<flavor>/jniLibs/ (full|noImages|noText|minimal)
./scripts/build-android-variants.sh              # all flavors
# VARIANT=full ./scripts/build-android-variants.sh

cd android
./gradlew :resvg-mobile:assembleFullRelease :resvg-mobile-ui:assembleRelease
./gradlew :demo:assembleDebug
# Other flavors: assembleNoImagesRelease | assembleNoTextRelease | assembleMinimalRelease
```

Gradle fails the build if native `.so` files are missing (no silent empty AARs). Set `SKIP_CARGO_NDK=1` if you already ran `build-android-variants.sh`.

```kotlin
import com.resvg.mobile.FitMode
import com.resvg.mobile.RenderOptions
import com.resvg.mobile.Resvg

// Default fit is INTRINSIC — works without width/height.
val bitmap = Resvg.renderBitmap(svgBytes)

// contain / cover / fill require both dimensions:
val sized = Resvg.renderBitmap(
  svgBytes,
  RenderOptions(width = 128u, height = 128u, fit = FitMode.CONTAIN, background = null),
  fonts = Resvg.loadAssetFontConfig(context),
)
```

Native library loaded by UniFFI/JNA: `libuniffi_resvg_mobile.so`.

### Coil 3 (`resvg-mobile-coil`)

Rasterize SVG through Coil’s pipeline (HTTP/file/asset/`ByteArray` fetchers stay Coil’s; we only decode):

```kotlin
implementation(project(":resvg-mobile-coil"))
// or Maven: com.resvg:resvg-mobile-coil:0.1.0
implementation("io.coil-kt.coil3:coil-compose:3.3.0")

val imageLoader = ImageLoader.Builder(context)
    .components { add(ResvgDecoder.Factory()) }
    // Optional default fonts for every request:
    // .resvgFonts(Resvg.loadAssetFontConfig(context))
    .build()

AsyncImage(
    model = ImageRequest.Builder(context)
        .data("file:///android_asset/sample.svg") // or ByteArray, File, https URL, …
        .resvgFonts(Resvg.loadAssetFontConfig(context)) // optional per-request
        .build(),
    contentDescription = null,
    imageLoader = imageLoader,
)
```

Requires **Kotlin 2.2+** (Coil 3.3). Demo app shows both `ResvgImage` and Coil `AsyncImage`.

## Rust API

```text
render(svg, RenderOptions { width, height, fit, background }) -> RenderedImage
render_with_fonts(svg, options, font_dirs) -> RenderedImage
render_with_font_config(svg, options, FontConfig { dirs, data, aliases, default_family }) -> RenderedImage
render_with_resources(svg, options, fonts, resources_dir?) -> RenderedImage  # relative image hrefs
intrinsic_size(svg) -> SizeF
```

`FitMode`: `Contain` | `Cover` | `Fill` | `Intrinsic`

- `Contain` / `Cover` / `Fill` require **both** width and height.
- `Intrinsic` uses SVG size when neither axis is set (or when both are set — both are ignored). Exactly one axis preserves aspect ratio.

Limits: either edge ≤ **8192** px, and `width * height` ≤ **2048²** pixels. SVG input ≤ **8 MiB**. Each `FontConfig.data` blob ≤ **12 MiB** (32 MiB total). At most **16** font directories, each an absolute path with no `..`.

UI wrappers additionally soft-cap each edge at **2048** px. Call render APIs off the main thread for large SVGs.

### Untrusted SVG

`render` / Coil do **not** open local files. Absolute image `href`s, `file:` URLs, and `http(s):` URLs are ignored (no network fetch). Pass `resources_dir` only for SVG you trust to read a folder: relative hrefs must stay inside that directory, or inside a `resources/` directory next to one of its ancestors (how the test suite resolves `../../../resources/...`). Symlinks that leave that jail are ignored. `FontConfig.dirs` is a separate trusted filesystem input — point it at app-owned font folders, not paths taken from the SVG.

## Fonts

Icon / path-only SVGs need **no** fonts — UI and render helpers default to `FontConfig.empty`.

For text, pass a single `fonts: FontConfig`:

| Field | Purpose |
|-------|---------|
| `dirs` | Folders of `.ttf` / `.otf` / `.ttc` |
| `data` | Raw font bytes (best on mobile — no filesystem extract) |
| `aliases` | Map SVG `font-family` → a loaded face (`"App Sans"` → `"Noto Sans"`) |
| `default_family` | Used when the SVG omits `font-family` |

```swift
let image = try Resvg.renderUIImage(
  data: svgData,
  fonts: Resvg.bundledFontConfig() // raw TTF bytes + default aliases
)
// Or add your own mapping:
let fonts = FontConfig(
  dirs: [],
  data: Resvg.bundledFontData(),
  aliases: Resvg.defaultFontAliases + [
    FontAlias(requested: "App Sans", replacement: "Noto Sans")
  ],
  defaultFamily: "Noto Sans"
)
```

```kotlin
val bitmap = Resvg.renderBitmap(
  svgBytes,
  fonts = Resvg.loadAssetFontConfig(context), // raw asset bytes + default aliases
)
// Or add your own mapping:
val fonts = fontConfig(
  data = Resvg.loadAssetFonts(context),
  aliases = Resvg.defaultFontAliases + FontAlias(requested = "App Sans", replacement = "Noto Sans"),
  defaultFamily = "Noto Sans",
)
```

Aliases are case-insensitive and also accept generic CSS families (`sans-serif`, `serif`, `monospace`, `cursive`, `fantasy`). `resvg` still skips text when the resolved family is not in the loaded set.

The Rust core caches the font database by directory list + data hashes so tiles do not re-parse TTFs on every render.

Builds without the Cargo `text` feature (Gradle `noText` / `minimal`, iOS `VARIANT=no-text|minimal`) keep the same `FontConfig` UniFFI APIs but ignore font input and never paint glyphs.

## Cross-platform SVG suite

Compare Rust host goldens, Android emulator, and iOS simulator renders of the same fixtures (SHA-256 of straight RGBA @ 512×512 Contain). Smoke (~57 cases: shapes, painting, structure including embedded/external images, paint servers, masking, filters) runs on every PR; full suite (~1,676 renders of ~1,679 SVGs, ≤2% failure gate) on the nightly workflow. External image hrefs use UniFFI `render_with_resources` with a synced vendor `resources/` tree. Details: [`rust/resvg-mobile/tests/suite/README.md`](rust/resvg-mobile/tests/suite/README.md).

```bash
./scripts/fetch-test-suite.sh
./scripts/generate-suite-goldens.sh smoke
./scripts/sync-suite-assets.sh smoke
MANIFEST=smoke ./scripts/run-android-suite.sh
MANIFEST=smoke ./scripts/run-ios-suite.sh
./scripts/compare-suite-results.py \
  --golden rust/resvg-mobile/tests/suite/goldens/smoke.jsonl \
  --android artifacts/suite/android-results.jsonl \
  --ios artifacts/suite/ios-results.jsonl
```

## Publishing

| Artifact | Notes |
|----------|--------|
| iOS | Run `./rust/build-ios.sh` (or `VARIANT=all`), then ship `ios/ResvgMobileFFI.xcframework` and/or `ios/variants/*/`. CI uploads zips per variant. Consumers cloning this repo must build an XCFramework before resolving the Swift package. |
| Android | From `android/`: `./gradlew publishToMavenLocal` publishes `resvg-mobile` (+ flavor artifactIds), `resvg-mobile-ui`, and `resvg-mobile-coil`. Remote Maven / GitHub Packages needs `publishing.repositories`, credentials, and (optionally) signing — not configured by default. |

CI (`.github/workflows/ci.yml`) runs Rust tests (including smoke goldens), builds all Android flavor AARs + demo, builds all iOS XCFramework variants, runs the smoke suite on Android emulator + iOS simulator, and compares results. Nightly full suite: `.github/workflows/suite-nightly.yml`.

## Binary size

Release profile uses `opt-level = "z"`, LTO, `panic = "abort"`, and symbol strip. UniFFI bindgen/`cli` is a host-only feature (`bindgen-cli`) so it is not linked into mobile libs.

### Size variants

| Variant | Cargo flags | Text/fonts | JPEG/GIF/WebP | arm64 `.so` (approx.) |
|---------|-------------|------------|---------------|------------------------|
| **full** (default) | `text,images` | yes | yes | ~2.9 MiB |
| **no-images** | `--no-default-features --features text` | yes | no | ~2.5 MiB |
| **no-text** | `--no-default-features --features images` | no | yes | ~1.5 MiB |
| **minimal** | `--no-default-features` | no | no | ~1.1 MiB |

```bash
# Android — all flavors into src/<flavor>/jniLibs/
./scripts/build-android-variants.sh
# or one: VARIANT=minimal ./scripts/build-android-variants.sh

# iOS XCFrameworks
./rust/build-ios.sh                         # full → ios/ResvgMobileFFI.xcframework
VARIANT=all ./rust/build-ios.sh             # also ios/variants/{full,no-images,no-text,minimal}/
```

Gradle product flavors: `full`, `noImages`, `noText`, `minimal` (demo/gallery default to `full`).
Maven local artifactIds: `resvg-mobile`, `resvg-mobile-no-images`, `resvg-mobile-no-text`, `resvg-mobile-minimal`.

UniFFI APIs stay the same across variants; without `text`, font helpers are no-ops and glyphs are skipped.
## License

Licensed under the [Apache License, Version 2.0](LICENSE).

See [NOTICE](NOTICE) for third-party attributions (resvg, UniFFI, JNA, …).
