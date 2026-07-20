#!/usr/bin/env python3
"""Extract evenly-spaced frames from a video and write ONE combined
$readmemh .mem file for frame_store.sv, reusing img_to_mem.py's own
grayscale/resize pipeline so every frame matches it exactly.

Usage:
    python tools/video_to_mem.py clip.mp4
    python tools/video_to_mem.py clip.mp4 --out sim/frame_store.mem --num-frames 24 --preview

IMPORTANT: --num-frames must equal the NUM_FRAMES parameter baked into
frame_store.sv / render_ctrl.sv / top.sv at synthesis time -- there is no
build-time link between this script and the RTL, so a mismatch will
silently raster-wrap into the wrong frame on hardware. The RTL default is
24; keep this script's default in sync with it.

Requires Pillow (pip install pillow) and ffmpeg/ffprobe on PATH.
"""
import argparse
import json
import os
import subprocess
import tempfile

from img_common import load_and_fit, save_preview, write_frame


def probe_duration(path: str) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", path],
        capture_output=True,
        text=True,
        check=True,
    )
    return float(json.loads(out.stdout)["format"]["duration"])


def extract_frame(video: str, t: float, out_png: str) -> None:
    result = subprocess.run(
        ["ffmpeg", "-y", "-ss", f"{t:.3f}", "-i", video, "-frames:v", "1", out_png],
        capture_output=True,
        check=True,
    )
    if not os.path.exists(out_png):
        # ffmpeg can exit 0 with no output frame if the seek lands past the
        # last decodable frame (duration rounding, VFR clips, etc).
        raise RuntimeError(
            f"ffmpeg produced no frame at t={t:.3f}s (exit 0, no output file). "
            f"stderr:\n{result.stderr.decode(errors='replace')}"
        )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="source video (any format ffmpeg can read)")
    ap.add_argument("--out", default="sim/frame_store.mem", help="output .mem path")
    ap.add_argument("--width", type=int, default=96)
    ap.add_argument("--height", type=int, default=64)
    ap.add_argument(
        "--num-frames",
        type=int,
        default=24,
        help="must match NUM_FRAMES in frame_store.sv/render_ctrl.sv/top.sv (default: 24)",
    )
    ap.add_argument(
        "--fit",
        choices=["cover", "contain", "stretch"],
        default="cover",
        help="cover: fill the frame, center-cropping overflow (default). "
        "contain: fit inside the frame, pad with black. "
        "stretch: resize directly, ignoring aspect ratio.",
    )
    ap.add_argument(
        "--preview", action="store_true", help="also save a PNG preview per frame (16x upscaled, nearest-neighbor)"
    )
    args = ap.parse_args()

    duration = probe_duration(args.input)
    preview_dir = args.out.rsplit(".", 1)[0] + "_preview"
    if args.preview:
        os.makedirs(preview_dir, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp, open(args.out, "w") as out_f:
        for i in range(args.num_frames):
            # Centered, evenly-spaced sampling across the clip's duration,
            # clamped away from the very end -- ffmpeg can silently produce
            # no output when seeking right up against (or past) the last
            # decodable frame, which duration rounding can put us at.
            t = min(duration * (i + 0.5) / args.num_frames, duration - 0.15)
            t = max(t, 0.0)
            png_path = os.path.join(tmp, f"frame_{i:03d}.png")
            extract_frame(args.input, t, png_path)

            img = load_and_fit(png_path, args.width, args.height, args.fit)
            write_frame(img, out_f)

            if args.preview:
                save_preview(img, os.path.join(preview_dir, f"frame_{i:03d}.png"), args.width, args.height)

    print(f"wrote {args.num_frames} frames ({args.width}x{args.height}) to {args.out}")
    if args.preview:
        print(f"wrote per-frame previews to {preview_dir}/")


if __name__ == "__main__":
    main()
