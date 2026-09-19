# Contributing

Thanks for contributing to **resvg-mobile**.

## License

By submitting a pull request, you agree that your contribution is licensed
under the Apache License, Version 2.0 (see `LICENSE` and `NOTICE`).

## Development

Run commands from the **repository root** unless noted:

```bash
# Rust unit + golden tests (default = full: text + images)
(cd rust && cargo test -p resvg-mobile)

# Also exercise size-variant feature sets before larger PRs
(cd rust && cargo test -p resvg-mobile --no-default-features)
(cd rust && cargo test -p resvg-mobile --no-default-features --features text)
(cd rust && cargo test -p resvg-mobile --no-default-features --features images)

# Regenerate UniFFI bindings (and optionally mobile packages)
./scripts/ci-build.sh
BUILD_IOS=1 ./scripts/ci-build.sh
BUILD_ANDROID=1 ./scripts/ci-build.sh
```

### Size variants

Cargo features `text` and `images` (default both on). Mobile packaging:

| Platform | Command |
|----------|---------|
| Android | `./scripts/build-android-variants.sh` → `android/resvg-mobile/src/<flavor>/jniLibs/` |
| iOS | `VARIANT=all ./rust/build-ios.sh` → `ios/variants/<name>/` + default full XCFramework |

Gradle flavors: `full`, `noImages`, `noText`, `minimal`. See the root README **Binary size** section.

Keep Android Kotlin under `android/resvg-mobile/src/main/java` and Swift under
`ios/Sources/ResvgMobile` in sync with `rust/resvg-mobile/src/resvg_mobile.udl`
after API changes — prefer regenerating via
`cargo run -p resvg-mobile --features bindgen-cli --bin uniffi-bindgen` /
`build-ios.sh` rather than hand-editing generated files.

## Pull requests

- Prefer small, focused PRs.
- Include a short description of *why* the change is needed.
- Run `(cd rust && cargo test -p resvg-mobile)` before opening the PR.
- If you touch Cargo features or native packaging, rebuild at least one non-`full` variant locally.
