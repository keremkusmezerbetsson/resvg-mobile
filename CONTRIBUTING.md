# Contributing

Thanks for contributing to **resvg-mobile**.

## License

By submitting a pull request, you agree that your contribution is licensed
under the Apache License, Version 2.0 (see `LICENSE` and `NOTICE`).

## Development

Run commands from the **repository root** unless noted:

```bash
# Rust unit + golden tests
(cd rust && cargo test -p resvg-mobile)

# Regenerate UniFFI bindings (and optionally mobile packages)
./scripts/ci-build.sh
BUILD_IOS=1 ./scripts/ci-build.sh
BUILD_ANDROID=1 ./scripts/ci-build.sh
```

Keep Android Kotlin under `android/resvg-mobile/src/main/java` and Swift under
`ios/Sources/ResvgMobile` in sync with `rust/resvg-mobile/src/resvg_mobile.udl`
after API changes — prefer regenerating via `uniffi-bindgen` / `build-ios.sh`
rather than hand-editing generated files.

## Pull requests

- Prefer small, focused PRs.
- Include a short description of *why* the change is needed.
- Run `(cd rust && cargo test -p resvg-mobile)` before opening the PR.
