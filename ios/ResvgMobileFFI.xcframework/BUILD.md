# ResvgMobileFFI.xcframework

Built by `./rust/build-ios.sh` (binary slices are gitignored; this note is tracked via [ResvgMobileFFI.BUILD.md](../ResvgMobileFFI.BUILD.md)).

## Default (full)

```bash
./rust/build-ios.sh
# → ios/ResvgMobileFFI.xcframework  (text + JPEG/GIF/WebP)
```

## Size variants

| Variant | Command | Text/fonts | JPEG/GIF/WebP |
|---------|---------|------------|---------------|
| full | `VARIANT=full ./rust/build-ios.sh` | yes | yes |
| no-images | `VARIANT=no-images ./rust/build-ios.sh` | yes | no |
| no-text | `VARIANT=no-text ./rust/build-ios.sh` | no | yes |
| minimal | `VARIANT=minimal ./rust/build-ios.sh` | no | no |
| all | `VARIANT=all ./rust/build-ios.sh` | writes `ios/variants/<name>/` and copies **full** here |

Approximate device staticlib size shrinks in the same order as Android `.so` sizes (see root README): full → no-images → no-text → minimal.

To use a non-full variant with the Swift package:

```bash
rm -rf ios/ResvgMobileFFI.xcframework
cp -R ios/variants/minimal/ResvgMobileFFI.xcframework ios/ResvgMobileFFI.xcframework
cp ios/ResvgMobileFFI.BUILD.md ios/ResvgMobileFFI.xcframework/BUILD.md
```

UniFFI APIs are identical across variants; without `text`, font helpers are no-ops and glyphs are skipped.
