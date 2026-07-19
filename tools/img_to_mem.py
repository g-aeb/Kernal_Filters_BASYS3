#!/usr/bin/env python3
"""Downsize any image to the PMOD OLEDrgb's 96x64 resolution and write it
out as a $readmemh-compatible grayscale .mem file for image_rom.

Usage:
    python tools/img_to_mem.py photo.jpg
    python tools/img_to_mem.py photo.jpg --out sim/test_image.mem --preview

Requires Pillow (pip install pillow).
"""
import argparse

from PIL import Image


def load_and_fit(path: str, width: int, height: int, mode: str) -> Image.Image:
    img = Image.open(path).convert("L")  # grayscale

    if mode == "stretch":
        return img.resize((width, height), Image.LANCZOS)

    src_w, src_h = img.size
    src_aspect = src_w / src_h
    dst_aspect = width / height

    if mode == "cover":
        # Scale to fill the target box, then center-crop the overflow.
        if src_aspect > dst_aspect:
            new_h = height
            new_w = round(height * src_aspect)
        else:
            new_w = width
            new_h = round(width / src_aspect)
        img = img.resize((new_w, new_h), Image.LANCZOS)
        left = (new_w - width) // 2
        top = (new_h - height) // 2
        return img.crop((left, top, left + width, top + height))

    # mode == "contain": scale to fit inside the target box, pad with black.
    if src_aspect > dst_aspect:
        new_w = width
        new_h = round(width / src_aspect)
    else:
        new_h = height
        new_w = round(height * src_aspect)
    img = img.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("L", (width, height), 0)
    canvas.paste(img, ((width - new_w) // 2, (height - new_h) // 2))
    return canvas


def write_mem(img: Image.Image, path: str) -> None:
    with open(path, "w") as f:
        for val in img.getdata():
            f.write(f"{val:02x}\n")


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
    write_mem(img, args.out)
    print(f"wrote {args.width}x{args.height} grayscale image to {args.out}")

    if args.preview:
        preview_path = args.out.rsplit(".", 1)[0] + "_preview.png"
        img.resize((args.width * 16, args.height * 16), Image.NEAREST).save(preview_path)
        print(f"wrote preview to {preview_path}")


if __name__ == "__main__":
    main()
