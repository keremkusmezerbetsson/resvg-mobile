# Building ResvgMobileFFI.xcframework

Native static libraries are **not** committed (they are large). Build locally
or download the `ios-xcframework` artifact from CI.

```bash
# from repo root
./rust/build-ios.sh
```

This regenerates Swift bindings under `Sources/ResvgMobile/Generated/` and
writes `ios/ResvgMobileFFI.xcframework` (device + simulator slices).

Requires: Rust stable, Xcode, and the `aarch64-apple-ios`,
`aarch64-apple-ios-sim`, and `x86_64-apple-ios` targets.
