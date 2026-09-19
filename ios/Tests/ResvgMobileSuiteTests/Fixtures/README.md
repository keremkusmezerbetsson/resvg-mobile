# Suite fixtures (synced — do not edit by hand)

Populated by `./scripts/sync-suite-assets.sh smoke|full`.

| Path | When | Notes |
| ---- | ---- | ----- |
| `suite/**/*.svg` | smoke + full | Render inputs (smoke: curated list; full: all vendor SVGs) |
| `resources/` | smoke + full | External image href targets from vendor `resources/` |
| `suite-fonts/` | full only | Vendor fonts when present |
| `manifest.txt` | always | `smoke` or `full` |
| `smoke.txt` | smoke | Copy of the curated path list |

Do **not** sync sibling PNGs under `suite/` — those are upstream **result goldens**, not inputs. Raster inputs live in `resources/`.
