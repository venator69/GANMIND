#!/usr/bin/env python3
"""Utilities for generating and converting the handwritten digit '2' fixtures.

All assets are 28x28 grayscale (0-255) sampled in Q8.8 fixed-point for the RTL.
This script requires Pillow (pip install pillow) for PNG/JPG round-trips.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import List, Tuple

from PIL import Image, ImageDraw

WIDTH = 28
HEIGHT = 28
PIXELS = WIDTH * HEIGHT
Q_FRAC = 8
DEFAULT_PREFIX = Path(__file__).with_suffix("")


def _clamp(val: int, lo: int = 0, hi: int = 255) -> int:
    return max(lo, min(hi, val))


def draw_number_two() -> List[int]:
    """Create a stylized '2' path using Pillow drawing primitives."""
    img = Image.new("L", (WIDTH, HEIGHT), 0)
    draw = ImageDraw.Draw(img)
    # Top bar
    draw.rectangle((4, 3, 23, 7), fill=255)
    # Upper curve
    draw.arc((2, 1, 25, 24), start=300, end=80, fill=220, width=2)
    # Diagonal middle stroke
    draw.line((20, 12, 6, 20), fill=200, width=2)
    # Bottom bar
    draw.rectangle((4, 21, 24, 24), fill=255)
    # Anti-alias / blur not required, keep crisp for mem export
    pixels = list(img.getdata())
    return pixels


def write_mem(path: Path, pixels: List[int]) -> None:
    if len(pixels) != PIXELS:
        raise ValueError(f"Expected {PIXELS} pixels, got {len(pixels)}")
    q_vals = [(pix << Q_FRAC) & 0xFFFF for pix in (_clamp(p) for p in pixels)]
    path.write_text("\n".join(f"{val:04x}" for val in q_vals) + "\n")


def read_mem(path: Path) -> List[int]:
    lines = [ln.strip() for ln in path.read_text().splitlines() if ln.strip()]
    if len(lines) != PIXELS:
        raise ValueError(f"Expected {PIXELS} entries, found {len(lines)}")
    pixels: List[int] = []
    for token in lines:
        raw = int(token, 16)
        if raw >= 1 << 15:
            raw -= 1 << 16
        pixels.append(_clamp(raw >> Q_FRAC))
    return pixels


def pixels_to_image(pixels: List[int], png_path: Path, jpg_path: Path) -> None:
    img = Image.new("L", (WIDTH, HEIGHT))
    img.putdata([_clamp(p) for p in pixels])
    png_path.parent.mkdir(parents=True, exist_ok=True)
    jpg_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(png_path, format="PNG")
    img.save(jpg_path, format="JPEG", quality=95)
    print(f"Wrote {png_path} and {jpg_path}")


def image_to_pixels(image_path: Path) -> List[int]:
    img = Image.open(image_path).convert("L").resize((WIDTH, HEIGHT))
    vals = list(img.getdata())
    return [_clamp(v) for v in vals]


def generate_assets(output_dir: Path) -> Tuple[Path, Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    mem_path = output_dir / "test_number_two.mem"
    png_path = output_dir / "test_number_two.png"
    jpg_path = output_dir / "test_number_two.jpg"

    pixels = draw_number_two()
    write_mem(mem_path, pixels)
    pixels_to_image(pixels, png_path, jpg_path)
    print(f"Generated digit '2' assets in {output_dir}")
    return mem_path, png_path, jpg_path


def mem_to_images(mem_path: Path, png_path: Path, jpg_path: Path) -> None:
    pixels = read_mem(mem_path)
    pixels_to_image(pixels, png_path, jpg_path)


def image_to_mem(image_path: Path, mem_path: Path) -> None:
    pixels = image_to_pixels(image_path)
    write_mem(mem_path, pixels)
    print(f"Wrote mem file {mem_path} from {image_path}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Digit '2' asset helper")
    sub = parser.add_subparsers(dest="cmd", required=True)

    gen = sub.add_parser("generate", help="Create default png/jpg/mem trio")
    gen.add_argument("--out", type=Path, default=DEFAULT_PREFIX.parent,
                     help="Output directory (default: script folder)")

    m2i = sub.add_parser("mem-to-image", help="Convert mem to png/jpg")
    m2i.add_argument("mem", type=Path)
    m2i.add_argument("png", type=Path)
    m2i.add_argument("jpg", type=Path)

    i2m = sub.add_parser("image-to-mem", help="Convert png/jpg to mem")
    i2m.add_argument("image", type=Path)
    i2m.add_argument("mem", type=Path)

    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.cmd == "generate":
        generate_assets(args.out)
    elif args.cmd == "mem-to-image":
        mem_to_images(args.mem, args.png, args.jpg)
    elif args.cmd == "image-to-mem":
        image_to_mem(args.image, args.mem)


if __name__ == "__main__":
    main()
