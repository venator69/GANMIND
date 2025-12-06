#!/usr/bin/env python3
"""DigitIdentificationTest sample preparation utilities.

This helper converts the PNG grids inside `Willthon/GANMIND/samples/` into the
28x28 Q8.8 fixed-point memory images consumed by the new digit identifier
simulation, and it can also render a `.mem` file back into a preview PNG for
quick sanity checks.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

from PIL import Image

WIDTH = 28
HEIGHT = 28
PIXELS = WIDTH * HEIGHT
Q_FRAC = 8
RESAMPLE_MODES = {
    "bicubic": Image.BICUBIC,
    "bilinear": Image.BILINEAR,
    "nearest": Image.NEAREST,
}

def _clamp_u8(value: float) -> int:
    return max(0, min(255, int(round(value))))

def _roi_box(img: Image.Image, roi: Sequence[float] | None) -> Tuple[int, int, int, int]:
    if roi is None:
        return (0, 0, img.width, img.height)
    if len(roi) != 4:
        raise ValueError("ROI must be four floats: left, top, width, height")
    left = max(0.0, min(1.0, roi[0])) * img.width
    top = max(0.0, min(1.0, roi[1])) * img.height
    width = max(1.0, roi[2] * img.width)
    height = max(1.0, roi[3] * img.height)
    right = min(img.width, int(round(left + width)))
    bottom = min(img.height, int(round(top + height)))
    return (int(round(left)), int(round(top)), right, bottom)

def _write_mem(path: Path, pixels: Iterable[int]) -> None:
    values = [(pix << Q_FRAC) & 0xFFFF for pix in pixels]
    lines = "\n".join(f"{val:04x}" for val in values)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(lines + "\n", encoding="ascii")

def _read_mem(path: Path) -> List[int]:
    tokens = [ln.strip() for ln in path.read_text(encoding="ascii").splitlines() if ln.strip()]
    if len(tokens) != PIXELS:
        raise ValueError(f"Expected {PIXELS} entries, found {len(tokens)} in {path}")
    pixels: List[int] = []
    for token in tokens:
        raw = int(token, 16)
        if raw >= 1 << 15:
            raw -= 1 << 16
        pixels.append(_clamp_u8(raw >> Q_FRAC))
    return pixels

def _pixels_to_image(pixels: Sequence[int]) -> Image.Image:
    if len(pixels) != PIXELS:
        raise ValueError(f"Expected {PIXELS} pixels, got {len(pixels)}")
    img = Image.new("L", (WIDTH, HEIGHT))
    img.putdata([_clamp_u8(p) for p in pixels])
    return img

def _image_to_pixels(source: Path, roi: Sequence[float] | None, method: str, normalize: bool) -> List[int]:
    img = Image.open(source).convert("L")
    img = img.crop(_roi_box(img, roi))
    img = img.resize((WIDTH, HEIGHT), resample=RESAMPLE_MODES[method])
    pixels = list(img.getdata())
    if normalize and pixels:
        hi = max(pixels)
        lo = min(pixels)
        span = max(1, hi - lo)
        pixels = [int(round((val - lo) * 255 / span)) for val in pixels]
    return [_clamp_u8(p) for p in pixels]

def cmd_from_image(args: argparse.Namespace) -> None:
    pixels = _image_to_pixels(args.image, args.roi, args.method, args.normalize)
    _write_mem(args.mem, pixels)
    print(f"Wrote {args.mem} from {args.image} using {args.method} resize")
    if args.preview:
        preview = Path(args.preview)
        preview.parent.mkdir(parents=True, exist_ok=True)
        img = _pixels_to_image(pixels).resize((WIDTH * 8, HEIGHT * 8), resample=Image.NEAREST)
        img.save(preview, format="PNG")
        print(f"Saved preview PNG to {preview}")

def cmd_to_image(args: argparse.Namespace) -> None:
    pixels = _read_mem(args.mem)
    img = _pixels_to_image(pixels).resize((WIDTH * 8, HEIGHT * 8), resample=Image.NEAREST)
    img.save(args.png, format="PNG")
    print(f"Rendered {args.mem} to {args.png}")

def _parse_roi(value: str | None) -> Sequence[float] | None:
    if value is None:
        return None
    parts = [float(tok) for tok in value.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("ROI must be 'left,top,width,height' with 0-1 floats")
    return parts

def build_arg_parser() -> argparse.ArgumentParser:
    default_image = Path("Willthon/GANMIND/samples/real_images.png")
    default_mem = Path("Willthon/GANMIND/src/DigitIdentificationTest/digit_identifier_sample.mem")
    parser = argparse.ArgumentParser(description="Digit identifier sample helper")
    sub = parser.add_subparsers(dest="cmd", required=True)

    from_image = sub.add_parser("from-image", help="Convert a PNG/JPG into a Q8.8 mem file")
    from_image.add_argument("--image", type=Path, default=default_image, help="Input PNG/JPG path")
    from_image.add_argument("--mem", type=Path, default=default_mem, help="Output mem path")
    from_image.add_argument("--preview", type=Path, help="Optional PNG preview output")
    from_image.add_argument("--method", choices=sorted(RESAMPLE_MODES.keys()), default="bicubic",
                             help="Resize kernel (default: bicubic)")
    from_image.add_argument("--roi", type=_parse_roi, help="Optional ROI as left,top,width,height (0-1)")
    from_image.add_argument("--normalize", action="store_true",
                             help="Normalize histogram to 0-255 before quantizing")
    from_image.set_defaults(func=cmd_from_image)

    to_image = sub.add_parser("to-image", help="Render a mem file back to PNG for inspection")
    to_image.add_argument("--mem", type=Path, default=default_mem, help="Source mem path")
    to_image.add_argument("--png", type=Path, default=default_mem.with_suffix(".png"),
                          help="PNG output (default: mem path with .png)")
    to_image.set_defaults(func=cmd_to_image)

    return parser

def main() -> None:
    parser = build_arg_parser()
    args = parser.parse_args()
    args.func(args)

if __name__ == "__main__":
    main()
