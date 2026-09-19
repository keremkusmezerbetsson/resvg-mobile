#!/usr/bin/env python3
"""Compare suite JSONL results: Android/iOS vs Rust goldens (+ pairwise).

Line format (TSV): path\\tsha256\\twidth\\theight

Exact SHA-256 is the primary gate. On mismatch (or --fuzzy always), compute
max-abs / MAE / %% pixels differing from paired RGBA dumps when available.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional, Tuple


Entry = Tuple[str, int, int]  # sha, w, h


@dataclass
class FuzzyMetrics:
    max_abs: int
    mae: float
    pct_diff: float
    rmse: float


def load_jsonl(path: Path) -> Dict[str, Entry]:
    out: Dict[str, Entry] = {}
    text = path.read_text(encoding="utf-8")
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            raise SystemExit(f"bad line in {path}: {raw!r}")
        rel, sha, w_s, h_s = parts
        out[rel] = (sha, int(w_s), int(h_s))
    return out


def load_rgba(dump_dir: Optional[Path], rel: str, w: int, h: int) -> Optional[bytes]:
    if dump_dir is None:
        return None
    rgba_path = dump_dir / f"{rel}.rgba"
    if not rgba_path.is_file():
        return None
    data = rgba_path.read_bytes()
    expected = w * h * 4
    if len(data) != expected:
        print(f"warn: {rgba_path} size {len(data)} != {expected}", file=sys.stderr)
        return None
    return data


def fuzzy_metrics(a: bytes, b: bytes) -> FuzzyMetrics:
    n = len(a)
    assert n == len(b) and n % 4 == 0
    max_abs = 0
    sum_abs = 0
    sum_sq = 0
    diff_pixels = 0
    pixels = n // 4
    for i in range(0, n, 4):
        pixel_diff = False
        for c in range(4):
            e = abs(a[i + c] - b[i + c])
            if e > max_abs:
                max_abs = e
            sum_abs += e
            sum_sq += e * e
            if e >= 1:
                pixel_diff = True
        if pixel_diff:
            diff_pixels += 1
    mae = sum_abs / n if n else 0.0
    rmse = (sum_sq / n) ** 0.5 if n else 0.0
    pct = (100.0 * diff_pixels / pixels) if pixels else 0.0
    return FuzzyMetrics(max_abs=max_abs, mae=mae, pct_diff=pct, rmse=rmse)


def write_png(path: Path, rgba: bytes, w: int, h: int) -> None:
    """Minimal RGBA PNG writer (no external deps)."""

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw.extend(rgba[y * stride : (y + 1) * stride])
    compressed = zlib.compress(bytes(raw), 9)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def abs_diff_rgba(a: bytes, b: bytes) -> bytes:
    out = bytearray(len(a))
    for i in range(0, len(a), 4):
        for c in range(3):
            out[i + c] = abs(a[i + c] - b[i + c])
        out[i + 3] = 255
    return bytes(out)


def side_by_side(a: bytes, b: bytes, w: int, h: int) -> Tuple[bytes, int, int]:
    out_w = w * 2
    out = bytearray(out_w * h * 4)
    stride_in = w * 4
    stride_out = out_w * 4
    for y in range(h):
        row = y * stride_out
        src = y * stride_in
        out[row : row + stride_in] = a[src : src + stride_in]
        out[row + stride_in : row + 2 * stride_in] = b[src : src + stride_in]
    return bytes(out), out_w, h


@dataclass
class Thresholds:
    max_abs: int
    pct_diff: float


def soft_pass(m: FuzzyMetrics, thr: Thresholds) -> bool:
    return m.max_abs <= thr.max_abs and m.pct_diff <= thr.pct_diff


def compare_pair(
    name: str,
    left: Dict[str, Entry],
    right: Dict[str, Entry],
    left_dump: Optional[Path],
    right_dump: Optional[Path],
    *,
    fuzzy_mode: str,
    thr: Thresholds,
    allow_soft: bool,
    diff_dir: Path,
) -> Tuple[int, int, int]:
    """Returns (exact_ok, soft_pass, hard_fail)."""
    exact_ok = soft = hard = 0
    paths = sorted(set(left) | set(right))
    for rel in paths:
        if rel not in left:
            print(f"FAIL {name} missing left: {rel}")
            hard += 1
            continue
        if rel not in right:
            print(f"FAIL {name} missing right: {rel}")
            hard += 1
            continue
        l_sha, l_w, l_h = left[rel]
        r_sha, r_w, r_h = right[rel]
        if (l_w, l_h) != (r_w, r_h):
            print(f"FAIL {name} size {rel}: {l_w}x{l_h} vs {r_w}x{r_h}")
            hard += 1
            continue
        if l_sha == r_sha:
            exact_ok += 1
            if fuzzy_mode != "always":
                continue
        elif fuzzy_mode == "never":
            print(f"FAIL {name} sha {rel}: {l_sha} != {r_sha}")
            hard += 1
            continue

        a = load_rgba(left_dump, rel, l_w, l_h)
        b = load_rgba(right_dump, rel, r_w, r_h)
        if a is None or b is None:
            if l_sha != r_sha:
                print(f"FAIL {name} sha {rel} (no RGBA dumps for fuzzy): {l_sha} != {r_sha}")
                hard += 1
            continue
        m = fuzzy_metrics(a, b)
        label = f"{name} {rel}: max_abs={m.max_abs} mae={m.mae:.4f} pct_diff={m.pct_diff:.4f}% rmse={m.rmse:.4f}"
        if l_sha == r_sha:
            print(f"ok   {label}")
            continue
        if allow_soft and soft_pass(m, thr):
            print(f"WARN soft-pass {label}")
            soft += 1
        else:
            print(f"FAIL {label}")
            hard += 1
            safe = rel.replace("/", "__")
            side, sw, sh = side_by_side(a, b, l_w, l_h)
            write_png(diff_dir / f"{safe}.side.png", side, sw, sh)
            write_png(diff_dir / f"{safe}.diff.png", abs_diff_rgba(a, b), l_w, l_h)
    return exact_ok, soft, hard


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--golden", type=Path, required=True)
    p.add_argument("--android", type=Path, default=None)
    p.add_argument("--ios", type=Path, default=None)
    p.add_argument("--android-dump", type=Path, default=None, help="dir of path.rgba dumps")
    p.add_argument("--ios-dump", type=Path, default=None)
    p.add_argument("--golden-dump", type=Path, default=None)
    p.add_argument(
        "--fuzzy",
        choices=("on-mismatch", "always", "never"),
        default="on-mismatch",
    )
    p.add_argument("--soft-pass", action="store_true", help="allow soft-pass on nightly thresholds")
    p.add_argument("--max-abs", type=int, default=int(os.environ.get("SUITE_MAX_ABS", "1")))
    p.add_argument(
        "--pct-diff",
        type=float,
        default=float(os.environ.get("SUITE_PCT_DIFF", "0.01")),
        help="max %% pixels differing (default 0.01)",
    )
    p.add_argument("--diff-dir", type=Path, default=Path("artifacts/suite/diffs"))
    args = p.parse_args()

    golden = load_jsonl(args.golden)
    thr = Thresholds(max_abs=args.max_abs, pct_diff=args.pct_diff)
    args.diff_dir.mkdir(parents=True, exist_ok=True)

    total_exact = total_soft = total_hard = 0

    if args.android:
        android = load_jsonl(args.android)
        e, s, h = compare_pair(
            "android↔golden",
            android,
            golden,
            args.android_dump,
            args.golden_dump,
            fuzzy_mode=args.fuzzy,
            thr=thr,
            allow_soft=args.soft_pass,
            diff_dir=args.diff_dir,
        )
        total_exact += e
        total_soft += s
        total_hard += h

    if args.ios:
        ios = load_jsonl(args.ios)
        e, s, h = compare_pair(
            "ios↔golden",
            ios,
            golden,
            args.ios_dump,
            args.golden_dump,
            fuzzy_mode=args.fuzzy,
            thr=thr,
            allow_soft=args.soft_pass,
            diff_dir=args.diff_dir,
        )
        total_exact += e
        total_soft += s
        total_hard += h

    if args.android and args.ios:
        android = load_jsonl(args.android)
        ios = load_jsonl(args.ios)
        e, s, h = compare_pair(
            "android↔ios",
            android,
            ios,
            args.android_dump,
            args.ios_dump,
            fuzzy_mode=args.fuzzy,
            thr=thr,
            allow_soft=args.soft_pass,
            diff_dir=args.diff_dir,
        )
        total_exact += e
        total_soft += s
        total_hard += h

    if not args.android and not args.ios:
        print("provide --android and/or --ios", file=sys.stderr)
        return 2

    print(
        f"summary: exact={total_exact} soft_pass={total_soft} hard_fail={total_hard} "
        f"(fuzzy={args.fuzzy} soft_pass={args.soft_pass})"
    )
    return 1 if total_hard else 0


if __name__ == "__main__":
    sys.exit(main())
