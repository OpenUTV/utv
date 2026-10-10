#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""OpenEXR recipes.

Most are built with oiiotool from a 16-bit TIFF staging sequence rendered by ffmpeg, so pixels move and carry a frame
counter. Compression types newer than oiiotool can write (HTJ2K, ZSTD) use the OpenEXR Python bindings instead.
"""

import os
import subprocess
import tempfile

from .core import FFMPEG, OIIOTOOL, BuildError, Result, py_module, recipe, seq_pattern
from .sequences import ALPHA_RAMP, frame_range, render_frames
from .sources import video_source

EXR = {"pattern": "motion", "frames": 24, "compression": "zip"}
NEEDS = (FFMPEG, OIIOTOOL)

COMPRESSIONS = ("none", "rle", "zips", "zip", "piz", "pxr24", "b44", "b44a", "dwaa", "dwab")


def oiio_exr(ctx, p, outdir, ops, prefix="beauty", alpha=True, out_flag="-o", stage=None):
    """Stage RGB(A) frames, run ``oiiotool --frames <range> src.#.tif <ops> -o prefix.#.exr`` and return a Result."""
    stage = stage or p
    with tempfile.TemporaryDirectory(dir=outdir) as work:
        if alpha:
            render_frames(ctx, stage, work, "src", "tif", "rgba64le", vf=ALPHA_RAMP)
        else:
            render_frames(ctx, stage, work, "src", "tif", "rgb48le")
        src = os.path.join(work, "src.#.tif")
        cmd = ["oiiotool", "--frames", frame_range(p), src, *ops]
        if p.get("compression"):
            cmd += ["--compression", p["compression"]]
        ctx.run(cmd + [out_flag, os.path.join(outdir, f"{prefix}.#.exr")])
    expect = {"kind": "sequence", "width": p["width"], "height": p["height"], "frames": p["frames"]}
    expect.update({"start": p["start"], "compression": p.get("compression")})
    return Result(seq_pattern(prefix, "exr", p["start"], p["frames"]), expect)


def size(p, scale=1.0):
    return f"{int(p['width'] * scale)}x{int(p['height'] * scale)}"


for _comp in COMPRESSIONS:

    @recipe(
        f"exr-half-{_comp}",
        f"EXR RGBA half float, {_comp} compression",
        tags=("sequence", "exr", "format", "compression") + (("smoke",) if _comp in ("zip", "dwaa") else ()),
        needs=NEEDS,
        **dict(EXR, compression=_comp),
    )
    def _exr_comp(ctx, p, outdir):
        return oiio_exr(ctx, p, outdir, ["-d", "half"])


@recipe(
    "exr-float32",
    "EXR RGBA 32-bit float, zip",
    tags=("sequence", "exr", "format", "float"),
    needs=NEEDS,
    **EXR,
)
def exr_float(ctx, p, outdir):
    return oiio_exr(ctx, p, outdir, ["-d", "float"])


def aov_ops(p):
    """Beauty RGBA plus diffuse and specular (half), normals and depth (float) and an object id (uint32)."""
    full = size(p)
    return [
        "--dup", "--ch", "R,G,B", "--mulc", "0.6", "--chnames", "diffuse.R,diffuse.G,diffuse.B", "--chappend",
        "--dup", "--ch", "R,G,B", "--mulc", "0.4", "--chnames", "specular.R,specular.G,specular.B", "--chappend",
        "--pattern", "fill:topleft=-1,-1,1:topright=1,-1,1:bottomleft=-1,1,1:bottomright=1,1,1", full, "3",
        "--chnames", "N.X,N.Y,N.Z", "--chappend",
        "--pattern", "fill:top=1:bottom=1000", full, "1", "--chnames", "depth.Z", "--chappend",
        "--pattern", "checker:width=64:height=64:color1=0:color2=1", full, "1", "--chnames", "id", "--chappend",
        "-d", "half",
        "-d", "N.X=float", "-d", "N.Y=float", "-d", "N.Z=float", "-d", "depth.Z=float", "-d", "id=uint",
    ]  # fmt: skip


@recipe(
    "exr-multilayer",
    "EXR single-part render layers: RGBA, diffuse.*, specular.*, N.* (float), depth.Z (float), id (uint32)",
    tags=("sequence", "exr", "layers", "smoke"),
    needs=NEEDS,
    **EXR,
)
def exr_multilayer(ctx, p, outdir):
    result = oiio_exr(ctx, p, outdir, aov_ops(p))
    result.expect["channels"] = ["R", "G", "B", "A", "diffuse.*", "specular.*", "N.*", "depth.Z", "id"]
    return result


@recipe(
    "exr-multilayer-dwab",
    "EXR render layers as exr-multilayer, DWAB lossy compression",
    tags=("sequence", "exr", "layers"),
    needs=NEEDS,
    **dict(EXR, compression="dwab"),
)
def exr_multilayer_dwab(ctx, p, outdir):
    return oiio_exr(ctx, p, outdir, aov_ops(p))


def multipart_ops(p, src, depth_scale=1.0):
    # OpenEXR requires every part to share one display window, so a smaller part only shrinks its data window.
    named = "oiio:subimagename"
    return [
        "--attrib", named, "rgba",
        src, "--ch", "R,G,B", "--mulc", "0.6", "--attrib", named, "diffuse", "--siappend",
        "--pattern", "fill:top=1:bottom=1000", size(p, depth_scale), "1", "--chnames", "Z", "-d", "Z=float",
        "--fullsize", f"{size(p)}+0+0",
        "--attrib", named, "depth", "--siappend",
        "-d", "half", "-d", "Z=float",
    ]  # fmt: skip


@recipe(
    "exr-multipart",
    "EXR multi-part: parts 'rgba', 'diffuse' and 'depth' (float Z)",
    tags=("sequence", "exr", "layers", "multipart"),
    needs=NEEDS,
    **EXR,
)
def exr_multipart(ctx, p, outdir):
    return _multipart(ctx, p, outdir, 1.0)


@recipe(
    "exr-multipart-mixed-res",
    "EXR multi-part where the 'depth' part's data window covers only the top-left quarter of the display window",
    tags=("sequence", "exr", "layers", "multipart", "edge"),
    needs=NEEDS,
    **EXR,
)
def exr_multipart_mixed(ctx, p, outdir):
    return _multipart(ctx, p, outdir, 0.5)


def _multipart(ctx, p, outdir, depth_scale):
    with tempfile.TemporaryDirectory(dir=outdir) as work:
        render_frames(ctx, p, work, "src", "tif", "rgba64le", vf=ALPHA_RAMP)
        src = os.path.join(work, "src.#.tif")
        cmd = ["oiiotool", "--frames", frame_range(p), src, *multipart_ops(p, src, depth_scale)]
        ctx.run(cmd + ["--compression", p["compression"], "-a", "-o", os.path.join(outdir, "beauty.#.exr")])
    expect = {"kind": "sequence", "width": p["width"], "height": p["height"], "frames": p["frames"]}
    expect.update({"start": p["start"], "parts": ["rgba", "diffuse", "depth"]})
    return Result(seq_pattern("beauty", "exr", p["start"], p["frames"]), expect)


@recipe(
    "exr-tiled",
    "EXR RGBA half, 64x64 tiles (single level)",
    tags=("sequence", "exr", "tiled"),
    needs=NEEDS,
    **EXR,
)
def exr_tiled(ctx, p, outdir):
    return oiio_exr(ctx, p, outdir, ["-d", "half", "--tile", "64", "64"])


@recipe(
    "exr-tiled-mipmap",
    "EXR RGBA half, tiled with a full MIP-map pyramid (texture-style)",
    tags=("sequence", "exr", "tiled", "edge"),
    needs=NEEDS,
    **EXR,
)
def exr_mipmap(ctx, p, outdir):
    return oiio_exr(ctx, p, outdir, ["-d", "half"], out_flag="-otex:fileformatname=openexr")


@recipe(
    "exr-overscan",
    "EXR whose data window is 10% larger than the 1920x1080 display window on every side (negative origin)",
    tags=("sequence", "exr", "datawindow", "edge"),
    needs=NEEDS,
    **EXR,
)
def exr_overscan(ctx, p, outdir):
    ox, oy = p["width"] // 10, p["height"] // 10
    stage = dict(p, width=p["width"] + 2 * ox, height=p["height"] + 2 * oy)
    ops = ["--origin", f"-{ox}-{oy}", "--fullsize", f"{p['width']}x{p['height']}+0+0", "-d", "half"]
    result = oiio_exr(ctx, p, outdir, ops, stage=stage)
    result.expect["data_window"] = [-ox, -oy, p["width"] + ox - 1, p["height"] + oy - 1]
    return result


@recipe(
    "exr-datawindow-crop",
    "EXR whose data window is a centred box half the size of the display window (pixels outside are empty)",
    tags=("sequence", "exr", "datawindow", "edge"),
    needs=NEEDS,
    **EXR,
)
def exr_crop(ctx, p, outdir):
    w, h = p["width"] // 2, p["height"] // 2
    ops = ["--crop", f"{w}x{h}+{p['width'] // 4}+{p['height'] // 4}", "-d", "half"]
    return oiio_exr(ctx, p, outdir, ops)


@recipe(
    "exr-luminance",
    "EXR luminance-only: a single Y channel (half)",
    tags=("sequence", "exr", "channels", "edge"),
    needs=NEEDS,
    **EXR,
)
def exr_luminance(ctx, p, outdir):
    ops = ["--chsum:weight=0.2126,0.7152,0.0722", "--chnames", "Y", "-d", "half"]
    return oiio_exr(ctx, p, outdir, ops, alpha=False)


@recipe(
    "exr-stereo-multiview",
    "EXR single-part stereo: left view in R,G,B,A and right view in right.R.. with a multiView attribute",
    tags=("sequence", "exr", "stereo", "layers"),
    needs=NEEDS,
    **EXR,
)
def exr_stereo(ctx, p, outdir):
    ops = [
        "--dup", "--ch", "R,G,B,A", "--mulc", "0.8,1,0.8,1",
        "--chnames", "right.R,right.G,right.B,right.A", "--chappend",
        # Space-separated: oiiotool 3.2 segfaults parsing a comma-separated string array.
        "--attrib:type=string[2]", "multiView", "left right",
        "-d", "half",
    ]  # fmt: skip
    result = oiio_exr(ctx, p, outdir, ops)
    result.expect["views"] = ["left", "right"]
    return result


@recipe(
    "exr-deep",
    "Deep EXR (one sample per pixel, Z plus RGBA) made with oiiotool --deepen",
    tags=("sequence", "exr", "deep", "edge"),
    needs=NEEDS,
    **dict(EXR, frames=6, width=960, height=540),
)
def exr_deep(ctx, p, outdir):
    ops = ["--pattern", "fill:top=1:bottom=100", size(p), "1", "--chnames", "Z", "--chappend", "--deepen", "-d", "half"]
    result = oiio_exr(ctx, p, outdir, ops)
    result.expect["deep"] = True
    return result


for _comp, _frames, _dtype in (("dwaa", 96, "half"), ("piz", 96, "half"), ("zip", 48, "float")):

    @recipe(
        f"exr-4k-{_comp}-{_dtype}",
        f"EXR RGBA {_dtype}, {_comp}, 4096x2160 with grain, {_frames} frames: playback throughput",
        tags=("sequence", "exr", "perf"),
        needs=NEEDS,
        **dict(EXR, compression=_comp, width=4096, height=2160, frames=_frames, pattern="grain", dtype=_dtype),
    )
    def _exr_perf(ctx, p, outdir):
        return oiio_exr(ctx, p, outdir, ["-d", p["dtype"]])


@recipe(
    "exr-4k-multilayer-perf",
    "EXR render layers (as exr-multilayer) at 4096x2160, zip, 48 frames: layered playback throughput",
    tags=("sequence", "exr", "perf", "layers"),
    needs=NEEDS,
    **dict(EXR, width=4096, height=2160, frames=48, pattern="grain"),
)
def exr_4k_multilayer(ctx, p, outdir):
    return oiio_exr(ctx, p, outdir, aov_ops(p))


# --------------------------------------------------------------------------------------------------------------------
# New compression types, written with the OpenEXR Python bindings (pip install OpenEXR numpy)
# --------------------------------------------------------------------------------------------------------------------

PY_EXR = (FFMPEG, py_module("OpenEXR"), py_module("numpy"))
PY_COMPRESSIONS = {"htj2k256": "HTJ2K256_COMPRESSION", "htj2k32": "HTJ2K32_COMPRESSION", "zstd": "ZSTD_COMPRESSION"}


def raw_frames(p):
    """Yield the recipe's frames as (height, width, 4) uint16 numpy arrays, straight from an ffmpeg pipe."""
    import numpy as np

    cmd = ["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "error"]
    cmd += ["-f", "lavfi", "-i", video_source(p["pattern"], p["width"], p["height"], p["fps"], p["seed"])]
    cmd += ["-vf", ALPHA_RAMP, "-frames:v", str(p["frames"]), "-f", "rawvideo", "-pix_fmt", "rgba64le", "-"]
    frame_bytes = p["width"] * p["height"] * 8
    with subprocess.Popen(cmd, stdout=subprocess.PIPE, stdin=subprocess.DEVNULL) as proc:
        for _ in range(p["frames"]):
            buf = proc.stdout.read(frame_bytes)
            if len(buf) != frame_bytes:
                raise BuildError("ffmpeg produced fewer frames than requested")
            yield np.frombuffer(buf, dtype="<u2").reshape(p["height"], p["width"], 4)
        proc.stdout.read()
    if proc.returncode:
        raise BuildError(f"ffmpeg exited {proc.returncode}")


for _comp, _attr in PY_COMPRESSIONS.items():

    @recipe(
        f"exr-half-{_comp}",
        f"EXR RGBA half, {_comp.upper()} compression (OpenEXR 3.4+; written with the OpenEXR Python bindings)",
        tags=("sequence", "exr", "format", "compression", "new"),
        needs=PY_EXR,
        **dict(EXR, compression=_comp, exr_attr=_attr),
    )
    def _exr_py(ctx, p, outdir):
        import numpy as np
        import OpenEXR

        if not hasattr(OpenEXR, p["exr_attr"]):
            raise BuildError(f"this OpenEXR Python module ({OpenEXR.__version__}) has no {p['exr_attr']}")
        header = {"compression": getattr(OpenEXR, p["exr_attr"]), "type": OpenEXR.scanlineimage}
        for i, rgba in enumerate(raw_frames(p)):
            pixels = (rgba.astype(np.float32) / 65535.0).astype(np.float16)
            with OpenEXR.File(header, {"RGBA": pixels}) as f:
                f.write(os.path.join(outdir, f"beauty.{p['start'] + i:04d}.exr"))
        expect = {"kind": "sequence", "width": p["width"], "height": p["height"], "frames": p["frames"]}
        expect.update({"start": p["start"], "compression": p["compression"]})
        return Result(seq_pattern("beauty", "exr", p["start"], p["frames"]), expect)
