#!/usr/bin/env python3
"""Downsize any image to the PMOD OLEDrgb's 96x64 resolution and write it
out as a $readmemh-compatible grayscale .mem file for image_rom.

Usage:
    python tools/img_to_mem.py photo.jpg
    python tools/img_to_mem.py photo.jpg --out sim/test_image.mem --preview

Requires Pillow (pip install pillow).
"""
import argparse

from img_common import load_and_fit, save_preview, write_frame


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", help="source image (any format Pillow can read)")
    ap.add_argument("--out", default="sim/test_image.mem", help="output .mem path")
    ap.add_argument("--width", type=int, default=96)
    ap.add_argument("--height", type=int, default=64)
    ap.add_argument(
        "--fit",
        choices=["cover", "contain", "stretch"],
        default="cover",
        help="cover: fill the frame, center-cropping overflow (default). "
        "contain: fit inside the frame, pad with black. "
        "stretch: resize directly, ignoring aspect ratio.",
    )
    ap.add_argument(
        "--preview", action="store_true", help="also save a PNG preview (16x upscaled, nearest-neighbor)"
    )
    args = ap.parse_args()

    img = load_and_fit(args.input, args.width, args.height, args.fit)
    with open(args.out, "w") as f:
        write_frame(img, f)
    print(f"wrote {args.width}x{args.height} grayscale image to {args.out}")

    if args.preview:
        preview_path = args.out.rsplit(".", 1)[0] + "_preview.png"
        save_preview(img, preview_path, args.width, args.height)
        print(f"wrote preview to {preview_path}")


if __name__ == "__main__":
    main()
