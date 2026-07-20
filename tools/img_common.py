"""Shared image-processing helpers for img_to_mem.py and video_to_mem.py.

Requires Pillow (pip install pillow).
"""
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


def write_frame(img: Image.Image, f) -> None:
    """Append one frame's pixels, raster order, as $readmemh-compatible hex lines."""
    for val in img.getdata():
        f.write(f"{val:02x}\n")


def save_preview(img: Image.Image, path: str, width: int, height: int, scale: int = 16) -> None:
    img.resize((width * scale, height * scale), Image.NEAREST).save(path)
