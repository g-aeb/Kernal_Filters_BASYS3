#!/usr/bin/env python3
"""Generate a synthetic grayscale test image as a $readmemh .mem file.

No external dependencies -- draws a diagonal gradient background, a solid
border frame, and a filled circle, which together give a clean mix of
straight and curved edges. Useful as the default image_rom payload before
a real downsized photo (see img_to_mem.py) is dropped in.
"""
import argparse


def make_image(width: int, height: int) -> list:
    img = [[0] * width for _ in range(height)]
    cx, cy = width / 2, height / 2
    radius = min(width, height) * 0.28
    for y in range(height):
        for x in range(width):
            val = int(255 * (x + y) / (width + height - 2))
            if x < 2 or x >= width - 2 or y < 2 or y >= height - 2:
                val = 40
            if (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2:
                val = 220
            img[y][x] = max(0, min(255, val))
    return img


def write_mem(img: list, path: str) -> None:
    with open(path, "w") as f:
        for row in img:
            for val in row:
                f.write(f"{val:02x}\n")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--width", type=int, default=96)
    ap.add_argument("--height", type=int, default=64)
    ap.add_argument("--out", default="test_image.mem")
    args = ap.parse_args()

    img = make_image(args.width, args.height)
    write_mem(img, args.out)
    print(f"wrote {args.width}x{args.height} test image to {args.out}")


if __name__ == "__main__":
    main()
