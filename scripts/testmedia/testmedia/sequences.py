#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Image-sequence recipes for every format other than EXR (see exr.py)."""

import os

from .core import FFMPEG, OIIOTOOL, Result, ffmpeg_encoder, frame_file, oiio_format, recipe, seq_pattern
from .sources import video_source

SEQ = {"pattern": "counter", "frames": 24}


def render_frames(ctx, p, outdir, prefix, ext, pix_fmt, vargs=(), vf=None, pad=4):
    """Write frames ``start .. start+frames-1`` of the recipe's pattern as ``outdir/prefix.NNNN.ext``."""
    cmd = ["ffmpeg", "-hide_banner", "-nostdin", "-y"]
    cmd += ["-f", "lavfi", "-i", video_source(p["pattern"], p["width"], p["height"], p["fps"], p["seed"])]
    if vf:
        cmd += ["-vf", vf]
    cmd += list(vargs) + ["-pix_fmt", pix_fmt, "-frames:v", str(p["frames"]), "-start_number", str(p["start"])]
    cmd += [os.path.join(outdir, f"{prefix}.%0{pad}d.{ext}")]
    ctx.run(cmd)


def stage_source(ctx, p, workdir, pix_fmt="rgb48le"):
    """16-bit TIFF frames of the recipe's pattern for oiiotool to convert; returns the oiiotool wildcard path."""
    render_frames(ctx, p, workdir, "src", "tif", pix_fmt)
    return os.path.join(workdir, "src.#.tif")


def seq_result(p, prefix, ext, pix_fmt, **expect):
    e = {"kind": "sequence", "width": p["width"], "height": p["height"], "frames": p["frames"], "start": p["start"]}
    e["pix_fmt"] = pix_fmt
    e.update(expect)
    return Result(seq_pattern(prefix, ext, p["start"], p["frames"]), e)


def frame_range(p):
    return f"{p['start']}-{p['start'] + p['frames'] - 1}"


ALPHA_RAMP = "format=rgba64le,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='65535*mod(X+N*16,W)/W'"

# name: (extension, ffmpeg encoder, pixel format, extra encoder args, filter, description, tags)
FFMPEG_SEQUENCES = {
    "png-8bit": ("png", "png", "rgb24", (), None, "PNG 8-bit RGB", ()),
    "png-16bit": ("png", "png", "rgb48be", (), None, "PNG 16-bit RGB", ("16bit",)),
    "png-rgba16": ("png", "png", "rgba64be", (), ALPHA_RAMP, "PNG 16-bit RGBA with a moving alpha ramp", ("alpha",)),
    "dpx-10bit": ("dpx", "dpx", "gbrp10le", (), None, "DPX 10-bit RGB (film scan / DI)", ("10bit",)),
    "dpx-12bit": ("dpx", "dpx", "gbrp12le", (), None, "DPX 12-bit RGB", ("12bit",)),
    "dpx-16bit": ("dpx", "dpx", "rgb48le", (), None, "DPX 16-bit RGB", ("16bit",)),
    "tiff-8bit": ("tif", "tiff", "rgb24", (), None, "TIFF 8-bit RGB, uncompressed", ()),
    "tiff-16bit-lzw": ("tif", "tiff", "rgb48le", ("-compression_algo", "lzw"), None, "TIFF 16-bit RGB, LZW", ()),
    "jpeg": ("jpg", "mjpeg", "yuvj444p", ("-q:v", "2"), None, "JPEG 4:4:4, high quality", ()),
    "tga": ("tga", "targa", "bgra", (), None, "Targa 8-bit with alpha", ("alpha", "legacy")),
    "sgi": ("sgi", "sgi", "rgb48be", (), None, "SGI 16-bit RGB", ("legacy",)),
    "bmp": ("bmp", "bmp", "bgr24", (), None, "Windows BMP 8-bit RGB", ("legacy",)),
    "hdr": ("hdr", "hdr", "gbrpf32le", (), None, "Radiance HDR (RGBE)", ("hdr",)),
}

for _name, (_ext, _enc, _pix, _vargs, _vf, _desc, _tags) in FFMPEG_SEQUENCES.items():

    @recipe(
        f"{_name}-seq",
        f"{_desc}, frames {SEQ['frames']} starting at 1001",
        tags=("sequence", "format", _ext) + _tags + (("smoke",) if _name in ("png-8bit", "dpx-10bit") else ()),
        needs=(FFMPEG, ffmpeg_encoder(_enc)),
        ext=_ext,
        encoder=_enc,
        pix=_pix,
        **SEQ,
    )
    def _ffmpeg_seq(ctx, p, outdir, _vargs=_vargs, _vf=_vf):
        render_frames(ctx, p, outdir, "frame", p["ext"], p["pix"], vargs=["-c:v", p["encoder"], *_vargs], vf=_vf)
        return seq_result(p, "frame", p["ext"], p["pix"])


# Formats ffmpeg cannot write (or writes poorly) go through oiiotool from a 16-bit TIFF staging sequence.
# name: (extension, oiiotool format name, output data type, compression or None, description)
OIIO_SEQUENCES = {
    "tiff-float32": ("tif", "tiff", "float", "zip", "TIFF 32-bit float RGB, deflate"),
    "tiff-half": ("tif", "tiff", "half", "zip", "TIFF 16-bit half float RGB"),
    "jxl": ("jxl", "jpegxl", "uint16", None, "JPEG XL 16-bit"),
    "webp": ("webp", "webp", "uint8", None, "WebP 8-bit lossy"),
}

for _name, (_ext, _fmt, _dtype, _comp, _desc) in OIIO_SEQUENCES.items():

    @recipe(
        f"{_name}-seq",
        f"{_desc}, frames {SEQ['frames']} starting at 1001",
        tags=("sequence", "format", _ext),
        needs=(FFMPEG, OIIOTOOL, oiio_format(_fmt)),
        ext=_ext,
        dtype=_dtype,
        compression=_comp or "",
        **SEQ,
    )
    def _oiio_seq(ctx, p, outdir):
        import tempfile

        with tempfile.TemporaryDirectory(dir=outdir) as work:
            src = stage_source(ctx, p, work)
            cmd = ["oiiotool", "--frames", frame_range(p), src, "-d", p["dtype"]]
            if p["compression"]:
                cmd += ["--compression", p["compression"]]
            ctx.run(cmd + ["-o", os.path.join(outdir, f"frame.#.{p['ext']}")])
        return seq_result(p, "frame", p["ext"], p["dtype"])


@recipe(
    "png-6k-grain-seq",
    "PNG 8-bit 6144x6144 with grain, 48 frames: the issue #96 decode-throughput case (~60 MB/frame)",
    tags=("sequence", "png", "perf"),
    needs=(FFMPEG, ffmpeg_encoder("png")),
    width=6144,
    height=6144,
    frames=48,
    pattern="grain",
)
def png_6k(ctx, p, outdir):
    render_frames(ctx, p, outdir, "frame", "png", "rgb24")
    return seq_result(p, "frame", "png", "rgb24")


@recipe(
    "dpx-4k-10bit-seq",
    "DPX 10-bit 4096x2160 with grain, 96 frames: DI playback throughput",
    tags=("sequence", "dpx", "perf", "10bit"),
    needs=(FFMPEG, ffmpeg_encoder("dpx")),
    width=4096,
    height=2160,
    frames=96,
    pattern="grain",
)
def dpx_4k(ctx, p, outdir):
    render_frames(ctx, p, outdir, "frame", "dpx", "gbrp10le", vargs=["-c:v", "dpx"])
    return seq_result(p, "frame", "dpx", "gbrp10le")


# --------------------------------------------------------------------------------------------------------------------
# Sequence naming and numbering edge cases
# --------------------------------------------------------------------------------------------------------------------


@recipe(
    "seq-padding-variants",
    "The same short PNG sequence with no padding, 3, 4, 6 and 8 digits, each in its own subfolder",
    tags=("sequence", "edge", "naming"),
    needs=(FFMPEG, ffmpeg_encoder("png")),
    width=640,
    height=360,
    frames=12,
    start=1,
    pattern="counter",
)
def seq_padding(ctx, p, outdir):
    for pad in (0, 3, 4, 6, 8):
        sub = os.path.join(outdir, f"pad{pad}")
        os.makedirs(sub)
        fmt = "%d" if pad == 0 else f"%0{pad}d"
        cmd = ["ffmpeg", "-hide_banner", "-nostdin", "-y", "-f", "lavfi"]
        cmd += ["-i", video_source(p["pattern"], p["width"], p["height"], p["fps"], p["seed"])]
        cmd += ["-frames:v", str(p["frames"]), "-start_number", str(p["start"]), os.path.join(sub, f"frame.{fmt}.png")]
        ctx.run(cmd)
    result = seq_result(p, "pad4/frame", "png", "rgb24")
    result.notes = "Subfolders pad0, pad3, pad4, pad6, pad8 hold the same frames with different zero padding."
    return result


@recipe(
    "seq-negative-frames",
    "PNG sequence numbered -0005 .. 0006, crossing zero",
    tags=("sequence", "edge", "naming"),
    needs=(FFMPEG, ffmpeg_encoder("png")),
    width=640,
    height=360,
    frames=12,
    start=-5,
    pattern="counter",
)
def seq_negative(ctx, p, outdir):
    # ffmpeg cannot write negative frame numbers, so render from 0 and rename into place.
    staged = dict(p, start=0)
    render_frames(ctx, staged, outdir, "tmp", "png", "rgb24")
    for i in range(p["frames"]):
        frame = p["start"] + i
        name = f"frame.-{abs(frame):04d}.png" if frame < 0 else frame_file("frame", "png", frame)
        os.replace(os.path.join(outdir, frame_file("tmp", "png", i)), os.path.join(outdir, name))
    result = seq_result(p, "frame", "png", "rgb24")
    result.path = "frame.-5-6#.png"
    return result


@recipe(
    "seq-single-frame",
    "A one-frame PNG 'sequence' (frame.1001.png), which should open as a still",
    tags=("sequence", "edge", "naming"),
    needs=(FFMPEG, ffmpeg_encoder("png")),
    frames=1,
    pattern="bars",
)
def seq_single(ctx, p, outdir):
    render_frames(ctx, p, outdir, "frame", "png", "rgb24")
    return Result(frame_file("frame", "png", p["start"]), {"kind": "still", "width": p["width"], "height": p["height"]})


@recipe(
    "seq-unicode-path",
    "PNG sequence in a folder and with a file name containing spaces and non-ASCII characters",
    tags=("sequence", "edge", "naming"),
    needs=(FFMPEG, ffmpeg_encoder("png")),
    width=640,
    height=360,
    frames=12,
    pattern="counter",
)
def seq_unicode(ctx, p, outdir):
    sub = os.path.join(outdir, "Shot 010 – ñandú 東京")
    os.makedirs(sub)
    render_frames(ctx, p, sub, "plate v001 é", "png", "rgb24")
    return seq_result(p, "Shot 010 – ñandú 東京/plate v001 é", "png", "rgb24")
