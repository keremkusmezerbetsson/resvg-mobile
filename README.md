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
  android/             # Gradle AARs: resvg-mobile + resvg-mobile-ui + demo
  examples/            # Sample SVG + iOS demo Xcode project
  scripts/ci-build.sh
```

## Quick start

### Rust tests

```bash
cd rust && cargo test -p resvg-mobile
```

### iOS (Swift Package)

```bash
./rust/build-ios.sh   # builds ResvgMobileFFI.xcframework + regenerates Swift
open ios/Package.swift
```

```swift
import ResvgMobile

let image = try Resvg.renderUIImage(
  data: svgData,
  options: RenderOptions(width: 128, height: 128, fit: .contain, background: nil),
  fontDirs: [] // empty for icons; pass system font dirs for text SVGs
)
```

Demo app: `examples/ios-demo/ResvgDemo.xcodeproj` (depends on the local SPM package).

### Android (AAR)

```bash
cargo install cargo-ndk
cd rust
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 \
  -o ../android/resvg-mobile/src/main/jniLibs \
  build -p resvg-mobile --release

cd ../android
./gradlew :resvg-mobile:assembleRelease :resvg-mobile-ui:assembleRelease
./gradlew :demo:assembleDebug
```

```kotlin
import com.resvg.mobile.FitMode
import com.resvg.mobile.RenderOptions
import com.resvg.mobile.Resvg

val bitmap = Resvg.renderBitmap(
  svgBytes,
  RenderOptions(width = 128u, height = 128u, fit = FitMode.CONTAIN, background = null),
  fontDirs = emptyList(), // empty for icons; use listOf("/system/fonts") for text
)
```

Native library loaded by UniFFI/JNA: `libuniffi_resvg_mobile.so`.

## Rust API

```text
render(svg, RenderOptions { width, height, fit, background }) -> RenderedImage
render_with_fonts(svg, options, font_dirs) -> RenderedImage
intrinsic_size(svg) -> SizeF
```

`FitMode`: `Contain` | `Cover` | `Fill` | `Intrinsic`  
Max edge: **8192** px. Cap UI renders further (e.g. 2048) on the wrappers.

Call `render` / `renderBitmap` / `renderUIImage` off the main thread for large SVGs.

## Fonts

Icon / path-only SVGs need **no** fonts — platform helpers default `fontDirs` to empty.
For text-bearing SVGs, pass:

| Platform | Typical dirs |
|----------|----------------|
| iOS | `/System/Library/Fonts`, `…/Core`, `…/Supplemental` |
| Android | `/system/fonts` |

## Publishing

| Artifact | Notes |
|----------|--------|
| iOS | Run `./rust/build-ios.sh`, then ship `ios/ResvgMobileFFI.xcframework` (CI uploads it as an artifact). Do not commit the large `.a` binaries. |
| Android | Publish `com.resvg:resvg-mobile` and `com.resvg:resvg-mobile-ui` via `./gradlew publishToMavenLocal` (or your Maven / GitHub Packages). |

CI (`.github/workflows/ci.yml`) runs Rust tests, builds Android AARs, and builds the iOS XCFramework.

## Binary size

Release profile uses LTO, size opts, and strip. Expect multi‑MB native libs (resvg stack).

## License

Licensed under the [Apache License, Version 2.0](LICENSE).

See [NOTICE](NOTICE) for third-party attributions (resvg, UniFFI, JNA, …).
