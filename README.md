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

## Layout

```
resvg-mobile/
  rust/resvg-mobile/   # Rust + UniFFI (cdylib / staticlib)
  ios/                 # Swift Package: ResvgMobile + ResvgMobileUI
  android/             # Gradle AARs: resvg-mobile + resvg-mobile-ui + demo + gallery
  examples/            # Sample SVG, iOS demo, iOS gallery
  scripts/             # fetch-test-suite.sh, sync-gallery-svgs.sh, ci-build.sh
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
```

### iOS (Swift Package)

Native libraries are **not** committed (they are large). Build them first:

```bash
./rust/build-ios.sh   # writes ios/ResvgMobileFFI.xcframework + regenerates Swift
open ios/Package.swift
```

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

The synced `resvg-suite/` trees are gitignored (~21 MB); run `sync-gallery-svgs.sh` after cloning.

### Android (AAR)

```bash
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

cd rust
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 \
  -o ../android/resvg-mobile/src/main/jniLibs \
  build -p resvg-mobile --release

cd ../android
./gradlew :resvg-mobile:assembleRelease :resvg-mobile-ui:assembleRelease
./gradlew :demo:assembleDebug
```

Gradle fails the build if native `.so` files are missing (no silent empty AARs).

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

## Rust API

```text
render(svg, RenderOptions { width, height, fit, background }) -> RenderedImage
render_with_fonts(svg, options, font_dirs) -> RenderedImage
render_with_font_config(svg, options, FontConfig { dirs, data, aliases, default_family }) -> RenderedImage
intrinsic_size(svg) -> SizeF
```

`FitMode`: `Contain` | `Cover` | `Fill` | `Intrinsic`

- `Contain` / `Cover` / `Fill` require **both** width and height.
- `Intrinsic` uses SVG size when neither axis is set (or when both are set — both are ignored). Exactly one axis preserves aspect ratio.

Limits: either edge ≤ **8192** px, and `width * height` ≤ **2048²** pixels.

UI wrappers additionally soft-cap each edge at **2048** px. Call render APIs off the main thread for large SVGs.

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

## Publishing

| Artifact | Notes |
|----------|--------|
| iOS | Run `./rust/build-ios.sh`, then ship `ios/ResvgMobileFFI.xcframework` (CI uploads a zip artifact). Consumers cloning this repo must build the XCFramework before resolving the Swift package. |
| Android | From `android/`: `./gradlew publishToMavenLocal`. Remote Maven / GitHub Packages needs `publishing.repositories`, credentials, and (optionally) signing — not configured by default. |

CI (`.github/workflows/ci.yml`) runs Rust tests, builds Android AARs + demo, builds the iOS XCFramework, and compiles the Swift package.

## Binary size

Release profile uses LTO, size opts, and strip. Expect multi‑MB native libs (resvg stack).

## License

Licensed under the [Apache License, Version 2.0](LICENSE).

See [NOTICE](NOTICE) for third-party attributions (resvg, UniFFI, JNA, …).
