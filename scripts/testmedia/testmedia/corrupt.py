#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Deliberately damaged media.

Each corrupt recipe copies a clean recipe's output and breaks it in one specific, seeded way. A reader is allowed to
reject the result or show errors for the damaged frames; it must not crash, hang or allocate unbounded memory.

The byte-level operations are also available on any file through ``utv_testmedia.py corrupt``.
"""

import os
import random
import shutil
import struct

from .core import FFMPEG, REGISTRY, BuildError, Result, ffmpeg_encoder, frame_file, recipe
from .sequences import render_frames

# --------------------------------------------------------------------------------------------------------------------
# Byte-level operations. All take an absolute path and modify the file in place.
# --------------------------------------------------------------------------------------------------------------------


def truncate(path, fraction=0.5):
    size = os.path.getsize(path)
    with open(path, "r+b") as f:
        f.truncate(int(size * fraction))


def bitflip(path, count=100, seed=1, start=0.1, end=1.0):
    """Flip one random bit in each of `count` random bytes between fractions `start` and `end` of the file."""
    rng = random.Random(seed)
    size = os.path.getsize(path)
    lo, hi = int(size * start), max(int(size * start) + 1, int(size * end) - 1)
    with open(path, "r+b") as f:
        for _ in range(count):
            pos = rng.randrange(lo, hi)
            f.seek(pos)
            byte = f.read(1)[0]
            f.seek(pos)
            f.write(bytes([byte ^ (1 << rng.randrange(8))]))


def zero_range(path, at=0.5, length=65536):
    size = os.path.getsize(path)
    pos = int(size * at)
    with open(path, "r+b") as f:
        f.seek(pos)
        f.write(b"\0" * min(length, size - pos))


def garbage(path, offset=0, length=256, seed=1):
    rng = random.Random(seed)
    with open(path, "r+b") as f:
        f.seek(offset)
        f.write(bytes(rng.randrange(256) for _ in range(length)))


def empty(path):
    open(path, "wb").close()


OPS = {
    "truncate": (truncate, "cut the file to FRACTION of its length (default 0.5)"),
    "bitflip": (bitflip, "flip COUNT random bits after the first 10%% of the file (default 100)"),
    "zero": (zero_range, "overwrite LENGTH bytes at FRACTION of the file with zeros (default 64 KiB at 0.5)"),
    "garbage": (garbage, "overwrite LENGTH bytes at OFFSET with random bytes (default the first 256)"),
    "empty": (empty, "make the file zero bytes long"),
}


# --------------------------------------------------------------------------------------------------------------------
# Format-aware operations
# --------------------------------------------------------------------------------------------------------------------


def exr_header_attribute(data, name):
    """Return (value offset, type, size) of a header attribute in a single-part scanline EXR."""
    pos = 8  # magic + version
    while pos < len(data) and data[pos] != 0:
        end = data.index(b"\0", pos)
        attr = data[pos:end].decode("latin-1")
        tend = data.index(b"\0", end + 1)
        kind = data[end + 1 : tend].decode("latin-1")
        (length,) = struct.unpack_from("<i", data, tend + 1)
        value = tend + 5
        if attr == name:
            return value, kind, length
        pos = value + length
    raise BuildError(f"EXR attribute {name!r} not found")


def exr_header_end(data):
    pos = 8
    while data[pos] != 0:
        end = data.index(b"\0", pos)
        tend = data.index(b"\0", end + 1)
        (length,) = struct.unpack_from("<i", data, tend + 1)
        pos = tend + 5 + length
    return pos + 1  # past the terminating null: the chunk offset table starts here


def exr_patch(path, fn):
    with open(path, "rb") as f:
        data = bytearray(f.read())
    fn(data)
    with open(path, "wb") as f:
        f.write(data)


def exr_huge_data_window(path):
    def patch(data):
        at, kind, _ = exr_header_attribute(data, "dataWindow")
        assert kind == "box2i"
        struct.pack_into("<iiii", data, at, 0, 0, 0x3FFFFFFF, 0x3FFFFFFF)

    exr_patch(path, patch)


def exr_bad_offsets(path, seed=1):
    def patch(data):
        rng = random.Random(seed)
        start = exr_header_end(data)
        for i in range(16):
            struct.pack_into("<Q", data, start + i * 8, rng.getrandbits(63))

    exr_patch(path, patch)


def dpx_huge_dimensions(path):
    """Set the DPX image element width and height (offsets 772 and 776) to 0x7FFFFFFF."""
    with open(path, "r+b") as f:
        magic = f.read(4)
        endian = ">" if magic == b"SDPX" else "<"
        f.seek(772)
        f.write(struct.pack(f"{endian}II", 0x7FFFFFFF, 0x7FFFFFFF))


def dpx_bad_data_offset(path):
    """Point the DPX image data offset (byte 4) past the end of the file."""
    with open(path, "r+b") as f:
        magic = f.read(4)
        endian = ">" if magic == b"SDPX" else "<"
        f.write(struct.pack(f"{endian}I", os.path.getsize(path) * 4))


def png_bad_idat_crc(path, seed=1):
    """Flip bits inside the first IDAT chunk's data without fixing its CRC."""
    with open(path, "rb") as f:
        data = f.read()
    idat = data.index(b"IDAT")
    (length,) = struct.unpack_from(">I", data, idat - 4)
    rng = random.Random(seed)
    with open(path, "r+b") as f:
        for _ in range(32):
            pos = idat + 4 + rng.randrange(length)
            f.seek(pos)
            byte = f.read(1)[0]
            f.seek(pos)
            f.write(bytes([byte ^ 0xFF]))


# --------------------------------------------------------------------------------------------------------------------
# Recipes
# --------------------------------------------------------------------------------------------------------------------


def copy_base(ctx, base_name, outdir, overrides=None):
    """Build (or reuse) a clean recipe and copy its output into `outdir`. Returns the base's meta."""
    base = REGISTRY[base_name]
    base_dir, meta = ctx.ensure(base, overrides)
    for entry in os.listdir(base_dir):
        if entry == "meta.json":
            continue
        src = os.path.join(base_dir, entry)
        dst = os.path.join(outdir, entry)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
    return meta


def file_corruption(name, base, help, op, tags=(), **kwargs):
    """Register a recipe that corrupts the single file a movie recipe produces."""
    base_recipe = REGISTRY[base]

    @recipe(name, help, tags=("corrupt",) + tuple(tags), needs=base_recipe.needs, base=base)
    def build(ctx, p, outdir):
        meta = copy_base(ctx, p["base"], outdir)
        op(os.path.join(outdir, meta["path"]), **kwargs)
        return Result(meta["path"], {"kind": meta["expect"].get("kind"), "base": p["base"]}, corrupt=True, notes=help)


def frame_corruption(name, base, help, op, frame_index=5, tags=(), **kwargs):
    """Register a recipe that corrupts one frame of a sequence recipe's output."""
    base_recipe = REGISTRY[base]

    @recipe(name, help, tags=("corrupt", "sequence") + tuple(tags), needs=base_recipe.needs, base=base)
    def build(ctx, p, outdir):
        meta = copy_base(ctx, p["base"], outdir)
        prefix, ext = sequence_prefix(meta["path"])
        frame = meta["params"]["start"] + frame_index
        op(os.path.join(outdir, frame_file(prefix, ext, frame)), **kwargs)
        expect = {"kind": "sequence", "base": p["base"], "damaged_frames": [frame]}
        return Result(meta["path"], expect, corrupt=True, notes=help)


def sequence_prefix(pattern):
    """``beauty.1001-1024#.exr`` -> (``beauty``, ``exr``)."""
    stem, ext = pattern.rsplit(".", 1)
    return stem.rsplit(".", 1)[0], ext


# Movies ------------------------------------------------------------------------------------------------------------

file_corruption(
    "corrupt-mp4-truncated-mdat",
    "h264-mp4",
    "Fast-start MP4 cut at 60%: the index (moov) is intact but the last 40% of the media data is missing",
    truncate,
    tags=("movie", "mp4", "h264"),
    fraction=0.6,
)


@recipe(
    "corrupt-mp4-missing-moov",
    "MP4 with the index written at the end (no fast start) cut at 60%, so the moov atom is gone entirely",
    tags=("corrupt", "movie", "mp4", "h264"),
    needs=REGISTRY["h264-mp4"].needs,
)
def corrupt_missing_moov(ctx, p, outdir):
    meta = copy_base(ctx, "h264-mp4", outdir, {"faststart": False})
    truncate(os.path.join(outdir, meta["path"]), 0.6)
    return Result(meta["path"], {"kind": "movie", "base": "h264-mp4"}, corrupt=True)


file_corruption(
    "corrupt-mp4-bitflips",
    "h264-mp4",
    "H.264 MP4 with 300 single-bit errors scattered through the media data",
    bitflip,
    tags=("movie", "mp4", "h264"),
    count=300,
)
file_corruption(
    "corrupt-hevc-bitflips",
    "hevc-mp4",
    "HEVC MP4 with 300 single-bit errors scattered through the media data",
    bitflip,
    tags=("movie", "mp4", "hevc"),
    count=300,
)
file_corruption(
    "corrupt-prores-zeroed",
    "prores-422-mov",
    "ProRes MOV with 256 KiB of zeros in the middle of the media data",
    zero_range,
    tags=("movie", "mov", "prores"),
    at=0.5,
    length=262144,
)
file_corruption(
    "corrupt-mov-header-garbage",
    "prores-422-mov",
    "ProRes MOV whose first 64 bytes (the ftyp and first atom headers) are random",
    garbage,
    tags=("movie", "mov", "prores"),
    offset=0,
    length=64,
)
file_corruption(
    "corrupt-mxf-truncated",
    "dnxhr-hq-mxf",
    "DNxHR MXF cut at 50% (footer partition and index missing)",
    truncate,
    tags=("movie", "mxf", "dnxhr"),
    fraction=0.5,
)


@recipe("corrupt-empty-movie", "A zero-byte file named clip.mov", tags=("corrupt", "movie", "mov"))
def corrupt_empty_movie(ctx, p, outdir):
    empty(os.path.join(outdir, "clip.mov"))
    return Result("clip.mov", {"kind": "movie"}, corrupt=True)


# Sequences ---------------------------------------------------------------------------------------------------------

frame_corruption(
    "corrupt-exr-truncated-frame",
    "exr-half-zip",
    "EXR sequence whose sixth frame is cut to half its length",
    truncate,
    tags=("exr",),
    fraction=0.5,
)
frame_corruption(
    "corrupt-exr-bitflip-frame",
    "exr-half-piz",
    "EXR sequence with 200 bit errors in the pixel data of the sixth frame",
    bitflip,
    tags=("exr",),
    count=200,
    start=0.2,
)
frame_corruption(
    "corrupt-exr-bad-magic",
    "exr-half-zip",
    "EXR sequence whose sixth frame has its magic number zeroed",
    garbage,
    tags=("exr",),
    offset=0,
    length=4,
)
frame_corruption(
    "corrupt-exr-zero-byte-frame",
    "exr-half-zip",
    "EXR sequence whose sixth frame is an empty file",
    empty,
    tags=("exr",),
)
frame_corruption(
    "corrupt-exr-huge-datawindow",
    "exr-half-zip",
    "EXR sequence whose sixth frame claims a 1 073 741 824-pixel-square data window (allocation guard test)",
    exr_huge_data_window,
    tags=("exr", "allocation"),
)
frame_corruption(
    "corrupt-exr-bad-offsets",
    "exr-half-zip",
    "EXR sequence whose sixth frame has random chunk offsets in its line offset table",
    exr_bad_offsets,
    tags=("exr",),
)
frame_corruption(
    "corrupt-exr-multilayer-truncated",
    "exr-multilayer",
    "Multi-layer EXR sequence whose sixth frame is cut to 70% of its length",
    truncate,
    tags=("exr", "layers"),
    fraction=0.7,
)
frame_corruption(
    "corrupt-png-bad-crc",
    "png-8bit-seq",
    "PNG sequence whose sixth frame has damaged IDAT data with a stale CRC",
    png_bad_idat_crc,
    tags=("png",),
)
frame_corruption(
    "corrupt-png-truncated",
    "png-8bit-seq",
    "PNG sequence whose sixth frame is cut to 40% of its length",
    truncate,
    tags=("png",),
    fraction=0.4,
)
frame_corruption(
    "corrupt-dpx-huge-dimensions",
    "dpx-10bit-seq",
    "DPX sequence whose sixth frame claims to be 2147483647 x 2147483647 (allocation guard test)",
    dpx_huge_dimensions,
    tags=("dpx", "allocation"),
)
frame_corruption(
    "corrupt-dpx-bad-data-offset",
    "dpx-10bit-seq",
    "DPX sequence whose sixth frame points its image data past the end of the file",
    dpx_bad_data_offset,
    tags=("dpx",),
)


@recipe(
    "corrupt-seq-missing-frames",
    "EXR sequence with frames 4-6 and 12 deleted (gaps in the numbering)",
    tags=("corrupt", "sequence", "exr"),
    needs=REGISTRY["exr-half-zip"].needs,
)
def corrupt_missing_frames(ctx, p, outdir):
    meta = copy_base(ctx, "exr-half-zip", outdir)
    prefix, ext = sequence_prefix(meta["path"])
    start = meta["params"]["start"]
    missing = [start + i for i in (3, 4, 5, 11)]
    for frame in missing:
        os.remove(os.path.join(outdir, frame_file(prefix, ext, frame)))
    return Result(meta["path"], {"kind": "sequence", "missing_frames": missing}, corrupt=True)


@recipe(
    "corrupt-seq-wrong-format-frame",
    "EXR sequence whose sixth frame is really a PNG file with an .exr name",
    tags=("corrupt", "sequence", "exr"),
    needs=REGISTRY["exr-half-zip"].needs + (ffmpeg_encoder("png"),),
)
def corrupt_wrong_format(ctx, p, outdir):
    meta = copy_base(ctx, "exr-half-zip", outdir)
    prefix, ext = sequence_prefix(meta["path"])
    frame = meta["params"]["start"] + 5
    params = dict(meta["params"], frames=1, start=frame)
    render_frames(ctx, params, outdir, "imposter", "png", "rgb24")
    os.replace(
        os.path.join(outdir, frame_file("imposter", "png", frame)), os.path.join(outdir, frame_file(prefix, ext, frame))
    )
    return Result(meta["path"], {"kind": "sequence", "damaged_frames": [frame]}, corrupt=True)


@recipe(
    "corrupt-seq-mixed-resolution",
    "PNG sequence whose sixth frame is half the resolution of the others",
    tags=("corrupt", "sequence", "png", "edge"),
    needs=(FFMPEG, ffmpeg_encoder("png")),
)
def corrupt_mixed_resolution(ctx, p, outdir):
    meta = copy_base(ctx, "png-8bit-seq", outdir)
    prefix, ext = sequence_prefix(meta["path"])
    frame = meta["params"]["start"] + 5
    params = dict(meta["params"], frames=1, start=frame)
    params.update(width=params["width"] // 2, height=params["height"] // 2)
    os.remove(os.path.join(outdir, frame_file(prefix, ext, frame)))
    render_frames(ctx, params, outdir, prefix, ext, "rgb24")
    return Result(meta["path"], {"kind": "sequence", "odd_frames": [frame]}, corrupt=True)
