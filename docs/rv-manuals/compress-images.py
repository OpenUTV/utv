#!/usr/bin/env python3
"""Make smaller copies of the manuals' images.

Reads every image the Typst manuals use (img("...") calls) from docs/images
and writes a copy to docs/images-web, which is what the manuals load. The
originals are never changed. Run it again after adding or replacing a
screenshot in docs/images:

    python3 compress-images.py            (needs Pillow: pip install pillow)

For each image it tries JPEG (quality 85 and 90) and a lossless PNG re-save,
and keeps the smallest that is at least 15% smaller than the original and
close enough to it (PSNR >= 38 dB, compared over white). Otherwise the
original is copied unchanged. The DPI is kept, so images display at the same
size. When an image changes from PNG to JPEG its name changes too; the
script lists any img() calls that must change to the new name.

Choices worth knowing before changing them:
  - Transparency is flattened onto white. Every output shows images on white
    (PDF pages, the light HTML theme, the dark theme's image backing).
  - JPEGs keep full color resolution (4:4:4). The default 4:2:0 ruins
    anaglyph fringes and colored UI text.
  - No 256-color palette PNGs: they score well but band UI gradients.
"""

import glob
import io
import math
import os
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "images")
OUT = os.path.join(HERE, "..", "images-web")
MIN_PSNR = 38.0
MIN_SAVING = 0.15


def flat(im):
    """The image as it is shown: composited onto white."""
    im = im.convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    return Image.alpha_composite(bg, im).convert("RGB")


def psnr(a, b):
    diff = ImageChops.difference(flat(a), flat(b))
    mse = sum(v * v for v in ImageStat.Stat(diff).rms) / 3
    return 99.0 if mse == 0 else 10 * math.log10(255 * 255 / mse)


def candidates(name, im):
    dpi = im.info.get("dpi", (72, 72))
    stem = os.path.splitext(name)[0]
    for quality in (85, 90):
        buf = io.BytesIO()
        flat(im).save(buf, "JPEG", quality=quality, optimize=True, progressive=True, subsampling=0, dpi=dpi)
        yield stem + ".jpg", buf.getvalue(), f"jpeg q{quality}"
    if im.format == "PNG":
        buf = io.BytesIO()
        im.save(buf, "PNG", optimize=True, dpi=dpi)
        yield name, buf.getvalue(), "png lossless"


def used_images():
    """{original file name: name used in the source}"""
    sources = glob.glob(os.path.join(HERE, "rv-*-manual", "*.typ"))
    sources += glob.glob(os.path.join(HERE, "rv-*-manual", "deprecated_docs", "*.typ"))
    text = "".join(Path(f).read_text(encoding="utf-8") for f in sources)
    # the source may already use the new (.jpg) name; find each one's original
    names = {}
    for name in re.findall(r'img\(\s*"([^"]+)"', text):
        stem = os.path.splitext(name)[0]
        found = [n for n in os.listdir(SRC) if os.path.splitext(n)[0] == stem]
        if not found:
            sys.exit(f"no original for {name} in {SRC}")
        names[found[0]] = name
    return dict(sorted(names.items()))


def main():
    os.makedirs(OUT, exist_ok=True)
    total_in = total_out = 0
    renames = {}
    for name, used_as in used_images().items():
        data = Path(SRC, name).read_bytes()
        im = Image.open(io.BytesIO(data))
        im.load()
        best = (name, data, "original")
        for out_name, out, how in candidates(name, im):
            if len(out) > (1 - MIN_SAVING) * len(data) or len(out) >= len(best[1]):
                continue
            if psnr(im, Image.open(io.BytesIO(out))) >= MIN_PSNR:
                best = (out_name, out, how)
        # drop a stale copy under the other extension
        for old in glob.glob(os.path.join(OUT, os.path.splitext(name)[0] + ".*")):
            os.remove(old)
        with open(os.path.join(OUT, best[0]), "wb") as f:
            f.write(best[1])
        if best[0] != used_as:
            renames[used_as] = best[0]
        total_in += len(data)
        total_out += len(best[1])
        print(f"{len(data) / 1e3:6.0f} -> {len(best[1]) / 1e3:6.0f} KB  {best[2]:12}  {name}")
    print(f"total {total_in / 1e6:.2f} MB -> {total_out / 1e6:.2f} MB")
    if renames:
        print("file names changed; update these img() calls:")
        for old, new in renames.items():
            print(f"  {old} -> {new}")


if __name__ == "__main__":
    main()
