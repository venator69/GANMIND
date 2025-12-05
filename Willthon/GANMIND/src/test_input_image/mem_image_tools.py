#!/usr/bin/env python3
"""Utility helpers to convert 28x28 Q8.8 .mem files to human-friendly images and back.

The script does not depend on external libraries. It writes/reads ASCII PGM (P2) files,
which can be opened by most image viewers (e.g., IrfanView, GIMP) or converted to PNG
with ImageMagick (`magick input.pgm output.png`).
"""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import List

WIDTH = 28
HEIGHT = 28
PIXELS = WIDTH * HEIGHT
Q_FRAC = 8
MAX_INT = 255


def read_mem(path: Path) -> List[int]:
    lines = [ln.strip() for ln in path.read_text().splitlines() if ln.strip()]
    if len(lines) != PIXELS:
        raise ValueError(f"Expected {PIXELS} entries, found {len(lines)} in {path}")
    values = []
    for idx, token in enumerate(lines):
        try:
            raw = int(token, 16)
        except ValueError as exc:
            raise ValueError(f"Line {idx+1}: '{token}' is not hex") from exc
        q88 = raw if raw < (1 << 15) else raw - (1 << 16)
        val = max(0, min(MAX_INT, q88 >> Q_FRAC))
        values.append(val)
    return values


def write_mem(path: Path, pixels: List[int]) -> None:
    if len(pixels) != PIXELS:
        raise ValueError(f"Expected {PIXELS} pixels, found {len(pixels)}")
    lines = []
    for val in pixels:
        clamped = max(0, min(MAX_INT, val))
        q88 = clamped << Q_FRAC
        lines.append(f"{q88 & 0xFFFF:04x}")
    path.write_text("\n".join(lines) + "\n")


def write_pgm(path: Path, pixels: List[int]) -> None:
    header = f"P2\n{WIDTH} {HEIGHT}\n{MAX_INT}\n"
    body_lines = []
    for row in range(HEIGHT):
        start = row * WIDTH
        row_vals = " ".join(str(pixels[start + col]) for col in range(WIDTH))
        body_lines.append(row_vals)
    path.write_text(header + "\n".join(body_lines) + "\n")


def read_pgm(path: Path) -> List[int]:
    with path.open("r") as f:
        magic = f.readline().strip()
        if magic != "P2":
            raise ValueError("Only ASCII PGM (P2) files are supported")
        dims_line = f.readline().strip()
        while dims_line.startswith("#"):
            dims_line = f.readline().strip()
        width, height = map(int, dims_line.split())
        if (width, height) != (WIDTH, HEIGHT):
            raise ValueError(f"Expected {WIDTH}x{HEIGHT}, got {width}x{height}")
        max_val_line = f.readline().strip()
        max_val = int(max_val_line)
        if max_val <= 0:
            raise ValueError("Invalid max value in PGM header")
        tokens = [token for token in f.read().split() if token]
    if len(tokens) != PIXELS:
        raise ValueError(f"Expected {PIXELS} pixels, found {len(tokens)}")
    pixels = []
    for token in tokens:
        val = int(token)
        val = int(round(val * (MAX_INT / max_val)))
        pixels.append(max(0, min(MAX_INT, val)))
    return pixels


def mem_to_pgm(mem_path: Path, pgm_path: Path) -> None:
    pixels = read_mem(mem_path)
    write_pgm(pgm_path, pixels)
    print(f"Wrote PGM image to {pgm_path}")


def pgm_to_mem(pgm_path: Path, mem_path: Path) -> None:
    pixels = read_pgm(pgm_path)
    write_mem(mem_path, pixels)
    print(f"Wrote Q8.8 mem file to {mem_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert between 28x28 Q8.8 .mem and PGM images")
    sub = parser.add_subparsers(dest="cmd", required=True)

    mem2pgm = sub.add_parser("mem-to-pgm", help="Convert .mem to ASCII PGM")
    mem2pgm.add_argument("mem", type=Path)
    mem2pgm.add_argument("pgm", type=Path)

    pgm2mem = sub.add_parser("pgm-to-mem", help="Convert ASCII PGM to .mem")
    pgm2mem.add_argument("pgm", type=Path)
    pgm2mem.add_argument("mem", type=Path)

    args = parser.parse_args()

    if args.cmd == "mem-to-pgm":
        mem_to_pgm(args.mem, args.pgm)
    elif args.cmd == "pgm-to-mem":
        pgm_to_mem(args.pgm, args.mem)


if __name__ == "__main__":
    main()
