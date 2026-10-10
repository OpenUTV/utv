#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Movie-file recipes, all encoded with ffmpeg."""

import json
import os
from fractions import Fraction

from .core import FFMPEG, Result, ffmpeg_encoder, recipe, which
from .sources import audio_source, fps_expr, video_source

# A moving horizontal alpha ramp, for codecs that carry alpha.
ALPHA_RAMP = "format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='255*mod(X+N*16,W)/W'"

AUDIO_CODECS = {"mp4": "aac", "mov": "aac", "mkv": "aac", "mxf": "pcm_s24le", "avi": "pcm_s16le", "ts": "mp2"}


def duration(p):
    return float(Fraction(fps_expr(p["fps"])) ** -1 * p["frames"])


def encode(ctx, p, outdir, ext, vargs, pix_fmt, vf=None, name="clip", out_args=(), audio_tracks=None, acodec=None):
    """Encode `p["frames"]` frames of the recipe's pattern (plus optional audio) into ``outdir/name.ext``."""
    path = os.path.join(outdir, f"{name}.{ext}")
    if audio_tracks is None:
        audio_tracks = [] if p.get("audio", "none") == "none" else [p["audio"]]

    cmd = ["ffmpeg", "-hide_banner", "-nostdin", "-y"]
    cmd += ["-f", "lavfi", "-i", video_source(p["pattern"], p["width"], p["height"], p["fps"], p["seed"])]
    for layout in audio_tracks:
        cmd += ["-f", "lavfi", "-i", audio_source(layout)]
    cmd += ["-map", "0:v"]
    for i in range(len(audio_tracks)):
        cmd += ["-map", f"{i + 1}:a"]
    if vf:
        cmd += ["-vf", vf]
    cmd += list(vargs) + ["-pix_fmt", pix_fmt]
    if audio_tracks:
        cmd += ["-c:a", acodec or AUDIO_CODECS.get(ext, "aac")]
        if (acodec or AUDIO_CODECS.get(ext, "aac")) == "aac":
            cmd += ["-b:a", "192k"]
    cmd += ["-frames:v", str(p["frames"]), "-t", f"{duration(p):.6f}"]
    cmd += list(out_args) + [path]
    ctx.run(cmd)

    expect = {
        "kind": "movie",
        "width": p["width"],
        "height": p["height"],
        "frames": p["frames"],
        "fps": p["fps"],
        "pix_fmt": pix_fmt,
        "audio": audio_tracks,
    }
    expect["probe"] = probe(path)
    return Result(os.path.basename(path), expect)


def probe(path):
    """Stream summary from ffprobe, recorded so tests can compare what UTV reports with what was written."""
    if not which("ffprobe"):
        return None
    import subprocess

    entries = (
        "stream=index,codec_type,codec_name,codec_tag_string,profile,pix_fmt,width,height,sample_aspect_ratio,"
        "r_frame_rate,nb_frames,field_order,color_range,color_space,color_transfer,color_primaries,channels,"
        "channel_layout:stream_side_data=side_data_type,rotation:format=format_name,duration"
    )
    proc = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", entries, "-of", "json", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    try:
        return json.loads(proc.stdout)
    except ValueError:
        return None


# --------------------------------------------------------------------------------------------------------------------
# H.264
# --------------------------------------------------------------------------------------------------------------------

X264 = (FFMPEG, ffmpeg_encoder("libx264"))
H264 = ["-c:v", "libx264", "-preset", "medium", "-crf", "18"]
MOVIE = {"pattern": "counter", "audio": "stereo"}


@recipe(
    "h264-mp4",
    "H.264 High 8-bit 4:2:0, 1080p24, 2 s GOP with B-frames, AAC stereo, fast-start MP4",
    tags=("movie", "codec", "h264", "mp4", "smoke"),
    needs=X264,
    faststart=True,
    gop=48,
    **MOVIE,
)
def h264_mp4(ctx, p, outdir):
    out = ["-movflags", "+faststart"] if p["faststart"] else []
    return encode(ctx, p, outdir, "mp4", H264 + ["-g", str(p["gop"]), "-bf", "2"], "yuv420p", out_args=out)


@recipe(
    "h264-intra-mp4",
    "H.264 all-intra (GOP 1), so every frame is a keyframe",
    tags=("movie", "codec", "h264", "mp4"),
    needs=X264,
    **MOVIE,
)
def h264_intra(ctx, p, outdir):
    return encode(ctx, p, outdir, "mp4", H264 + ["-g", "1", "-bf", "0"], "yuv420p")


@recipe(
    "h264-10bit-422-mov",
    "H.264 High 4:2:2 10-bit in QuickTime (camera/intermediate style)",
    tags=("movie", "codec", "h264", "mov", "10bit"),
    needs=X264,
    **MOVIE,
)
def h264_10bit(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", H264 + ["-profile:v", "high422"], "yuv422p10le")


@recipe(
    "h264-odd-dims-mp4",
    "H.264 4:4:4 at 1919x1081: odd width and height",
    tags=("movie", "codec", "h264", "mp4", "edge"),
    needs=X264,
    width=1919,
    height=1081,
    **MOVIE,
)
def h264_odd(ctx, p, outdir):
    return encode(ctx, p, outdir, "mp4", H264 + ["-profile:v", "high444"], "yuv444p")


@recipe(
    "h264-anamorphic-mov",
    "H.264 1440x1080 with 4:3 pixel aspect (displays as 1920x1080)",
    tags=("movie", "codec", "h264", "mov", "edge", "aspect"),
    needs=X264,
    width=1440,
    height=1080,
    **MOVIE,
)
def h264_anamorphic(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", H264, "yuv420p", vf="setsar=4/3")


@recipe(
    "h264-rotated-mp4",
    "H.264 with a 90-degree display-matrix rotation (phone footage)",
    tags=("movie", "codec", "h264", "mp4", "edge", "orientation"),
    needs=X264,
    width=1920,
    height=1080,
    rotation=90,
    **MOVIE,
)
def h264_rotated(ctx, p, outdir):
    # -display_rotation is an input option, and it only survives a stream copy, so encode first and then remux.
    staged = encode(ctx, p, outdir, "mp4", H264, "yuv420p", name="unrotated")
    src = os.path.join(outdir, staged.path)
    dst = os.path.join(outdir, "clip.mp4")
    ctx.run(["ffmpeg", "-hide_banner", "-nostdin", "-y", "-display_rotation", str(p["rotation"]), "-i", src,
             "-c", "copy", "-map", "0", dst])  # fmt: skip
    os.remove(src)
    staged.path = "clip.mp4"
    staged.expect["rotation"] = p["rotation"]
    staged.expect["probe"] = probe(dst)
    return staged


@recipe(
    "h264-vfr-mkv",
    "H.264 variable frame rate: an irregular subset of frames keeps its original timestamps",
    tags=("movie", "codec", "h264", "mkv", "edge", "timing"),
    needs=X264,
    frames=48,
    **MOVIE,
)
def h264_vfr(ctx, p, outdir):
    # Keep frames where n mod 5 is 0, 1 or 3: gaps of one and two frames. Timestamps are kept, so output is VFR.
    vf = "select='lt(mod(n\\,5)\\,2)+eq(mod(n\\,5)\\,3)'"
    kept = [n for n in range(p["frames"]) if n % 5 in (0, 1, 3)]
    result = encode(ctx, p, outdir, "mkv", H264 + ["-fps_mode", "vfr"], "yuv420p", vf=vf)
    # A reader on a constant-rate timeline spans first to last kept frame, repeating frames across the gaps.
    result.expect.update(frames=kept[-1] + 1, unique_frames=len(kept))
    result.notes = "Timestamps follow the source 24 fps clock with one- and two-frame gaps."
    return result


@recipe(
    "h264-interlaced-mov",
    "H.264 interlaced, top field first, 1080i29.97",
    tags=("movie", "codec", "h264", "mov", "edge", "interlaced"),
    needs=X264,
    fps=29.97,
    **MOVIE,
)
def h264_interlaced(ctx, p, outdir):
    vargs = H264 + ["-flags", "+ildct+ilme", "-x264-params", "tff=1", "-field_order", "tt"]
    return encode(ctx, p, outdir, "mov", vargs, "yuv420p")


@recipe(
    "h264-timecode-mov",
    "H.264 23.976 with a QuickTime timecode track starting 01:00:00:00",
    tags=("movie", "codec", "h264", "mov", "timecode"),
    needs=X264,
    fps=23.976,
    timecode="01:00:00:00",
    **MOVIE,
)
def h264_timecode(ctx, p, outdir):
    result = encode(ctx, p, outdir, "mov", H264, "yuv420p", out_args=["-timecode", p["timecode"]])
    result.expect["timecode"] = p["timecode"]
    return result


@recipe(
    "h264-multi-audio-mov",
    "H.264 with two audio tracks: stereo, then 5.1",
    tags=("movie", "codec", "h264", "mov", "audio"),
    needs=X264,
    **MOVIE,
)
def h264_multi_audio(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", H264, "yuv420p", audio_tracks=["stereo", "5.1"])


for _layout in ("mono", "5.1", "7.1"):
    _slug = _layout.replace(".", "")

    @recipe(
        f"h264-audio-{_slug}-mov",
        f"H.264 with {_layout} PCM audio, one tone per channel",
        tags=("movie", "audio", "h264", "mov"),
        needs=X264,
        pattern="counter",
        audio=_layout,
    )
    def _h264_audio(ctx, p, outdir):
        return encode(ctx, p, outdir, "mov", H264, "yuv420p", acodec="pcm_s24le")


@recipe(
    "h264-no-audio-mp4",
    "H.264 with no audio track",
    tags=("movie", "codec", "h264", "mp4", "audio"),
    needs=X264,
    pattern="counter",
    audio="none",
)
def h264_no_audio(ctx, p, outdir):
    return encode(ctx, p, outdir, "mp4", H264, "yuv420p")


@recipe(
    "h264-fullrange-mp4",
    "H.264 tagged full range (0-255), as screen recorders and some phones write",
    tags=("movie", "codec", "h264", "mp4", "color"),
    needs=X264,
    **MOVIE,
)
def h264_fullrange(ctx, p, outdir):
    return encode(ctx, p, outdir, "mp4", H264 + ["-color_range", "pc"], "yuv420p")


@recipe(
    "h264-long-gop-seek-mp4",
    "H.264 720p, 1 minute, 10 s GOP: worst case for scrubbing and random access",
    tags=("movie", "h264", "mp4", "perf", "seek"),
    needs=X264,
    width=1280,
    height=720,
    frames=1440,
    gop=240,
    **MOVIE,
)
def h264_long_gop(ctx, p, outdir):
    return encode(ctx, p, outdir, "mp4", H264 + ["-g", str(p["gop"]), "-keyint_min", str(p["gop"])], "yuv420p")


@recipe(
    "h264-4k60-mp4",
    "H.264 UHD 3840x2160 at 60 fps with grain: decode throughput",
    tags=("movie", "h264", "mp4", "perf"),
    needs=X264,
    width=3840,
    height=2160,
    fps=60.0,
    frames=240,
    pattern="grain",
    audio="stereo",
)
def h264_4k60(ctx, p, outdir):
    return encode(ctx, p, outdir, "mp4", H264 + ["-preset", "fast"], "yuv420p", out_args=["-movflags", "+faststart"])


# --------------------------------------------------------------------------------------------------------------------
# HEVC
# --------------------------------------------------------------------------------------------------------------------

X265 = (FFMPEG, ffmpeg_encoder("libx265"))
HEVC = ["-c:v", "libx265", "-preset", "medium", "-crf", "20", "-tag:v", "hvc1", "-x265-params", "log-level=error"]


@recipe(
    "hevc-mp4",
    "HEVC Main 8-bit 1080p24, hvc1-tagged MP4 (plays in QuickTime)",
    tags=("movie", "codec", "hevc", "mp4", "smoke"),
    needs=X265,
    **MOVIE,
)
def hevc_mp4(ctx, p, outdir):
    return encode(ctx, p, outdir, "mp4", HEVC, "yuv420p")


@recipe(
    "hevc-main10-mov",
    "HEVC Main 10 4:2:0 in QuickTime",
    tags=("movie", "codec", "hevc", "mov", "10bit"),
    needs=X265,
    pattern="gradient",
    audio="stereo",
)
def hevc_main10(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", HEVC, "yuv420p10le")


@recipe(
    "hevc-422-10bit-mov",
    "HEVC Main 4:2:2 10 (camera codec profile)",
    tags=("movie", "codec", "hevc", "mov", "10bit"),
    needs=X265,
    **MOVIE,
)
def hevc_422(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", HEVC, "yuv422p10le")


HDR10_PARAMS = (
    "log-level=error:hdr10=1:hdr10-opt=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:"
    "master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,50):max-cll=1000,400"
)
BT2020 = ["-color_primaries", "bt2020", "-colorspace", "bt2020nc"]


@recipe(
    "hevc-hdr10-pq-mov",
    "HEVC Main 10 HDR10: BT.2020 primaries, PQ transfer, mastering display and MaxCLL metadata",
    tags=("movie", "codec", "hevc", "mov", "hdr", "color", "10bit"),
    needs=X265,
    pattern="gradient",
    audio="stereo",
)
def hevc_hdr10(ctx, p, outdir):
    vargs = ["-c:v", "libx265", "-crf", "20", "-tag:v", "hvc1", "-x265-params", HDR10_PARAMS]
    return encode(ctx, p, outdir, "mov", vargs + BT2020 + ["-color_trc", "smpte2084"], "yuv420p10le")


@recipe(
    "hevc-hlg-mov",
    "HEVC Main 10 HLG: BT.2020 primaries, ARIB STD-B67 transfer",
    tags=("movie", "codec", "hevc", "mov", "hdr", "color", "10bit"),
    needs=X265,
    pattern="gradient",
    audio="stereo",
)
def hevc_hlg(ctx, p, outdir):
    params = "log-level=error:colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc"
    vargs = ["-c:v", "libx265", "-crf", "20", "-tag:v", "hvc1", "-x265-params", params]
    return encode(ctx, p, outdir, "mov", vargs + BT2020 + ["-color_trc", "arib-std-b67"], "yuv420p10le")


@recipe(
    "hevc-4k-mp4",
    "HEVC Main 10 UHD 3840x2160 at 24 fps with grain: decode throughput",
    tags=("movie", "hevc", "mp4", "perf"),
    needs=X265,
    width=3840,
    height=2160,
    frames=96,
    pattern="grain",
    audio="stereo",
)
def hevc_4k(ctx, p, outdir):
    return encode(ctx, p, outdir, "mp4", HEVC[:2] + ["-preset", "fast"] + HEVC[4:], "yuv420p10le")


# --------------------------------------------------------------------------------------------------------------------
# ProRes, DNxHR/DNxHD, CineForm: intra-frame editorial and finishing codecs
# --------------------------------------------------------------------------------------------------------------------

PRORES = (FFMPEG, ffmpeg_encoder("prores_ks"))
PRORES_PROFILES = {"proxy": 0, "lt": 1, "422": 2, "hq": 3}

for _name, _profile in PRORES_PROFILES.items():

    @recipe(
        f"prores-{_name}-mov",
        f"Apple ProRes 422 {_name.upper() if _name != '422' else ''}".rstrip() + " 10-bit 4:2:2, PCM audio",
        tags=("movie", "codec", "prores", "mov", "intra", "10bit") + (("smoke",) if _name == "422" else ()),
        needs=PRORES,
        profile=_profile,
        **MOVIE,
    )
    def _prores(ctx, p, outdir):
        vargs = ["-c:v", "prores_ks", "-profile:v", str(p["profile"]), "-vendor", "apl0"]
        return encode(ctx, p, outdir, "mov", vargs, "yuv422p10le", acodec="pcm_s24le")


@recipe(
    "prores-4444-alpha-mov",
    "Apple ProRes 4444 with a moving alpha ramp",
    tags=("movie", "codec", "prores", "mov", "intra", "alpha", "10bit"),
    needs=PRORES,
    **MOVIE,
)
def prores_4444(ctx, p, outdir):
    vargs = ["-c:v", "prores_ks", "-profile:v", "4", "-vendor", "apl0", "-alpha_bits", "16"]
    return encode(ctx, p, outdir, "mov", vargs, "yuva444p10le", vf=ALPHA_RAMP, acodec="pcm_s24le")


@recipe(
    "prores-4444xq-mov",
    "Apple ProRes 4444 XQ, no alpha",
    tags=("movie", "codec", "prores", "mov", "intra", "10bit"),
    needs=PRORES,
    **MOVIE,
)
def prores_4444xq(ctx, p, outdir):
    vargs = ["-c:v", "prores_ks", "-profile:v", "5", "-vendor", "apl0"]
    return encode(ctx, p, outdir, "mov", vargs, "yuv444p10le", acodec="pcm_s24le")


@recipe(
    "prores-hq-4k-mov",
    "Apple ProRes 422 HQ, 4096x2160 at 24 fps with grain: decode throughput",
    tags=("movie", "prores", "mov", "perf", "intra"),
    needs=PRORES,
    width=4096,
    height=2160,
    frames=96,
    pattern="grain",
    audio="stereo",
)
def prores_hq_4k(ctx, p, outdir):
    vargs = ["-c:v", "prores_ks", "-profile:v", "3", "-vendor", "apl0"]
    return encode(ctx, p, outdir, "mov", vargs, "yuv422p10le", acodec="pcm_s24le")


DNX = (FFMPEG, ffmpeg_encoder("dnxhd"))
DNXHR_PROFILES = {
    "lb": "yuv422p",
    "sq": "yuv422p",
    "hq": "yuv422p",
    "hqx": "yuv422p10le",
    "444": "yuv444p10le",
}

for _name, _pix in DNXHR_PROFILES.items():
    for _ext in ("mov", "mxf") if _name in ("hq", "hqx") else ("mov",):

        @recipe(
            f"dnxhr-{_name}-{_ext}",
            f"Avid DNxHR {_name.upper()} ({_pix}) in {'MXF OP1a' if _ext == 'mxf' else 'QuickTime'}",
            tags=("movie", "codec", "dnxhr", _ext, "intra") + (("10bit",) if "10" in _pix else ()),
            needs=DNX,
            profile=f"dnxhr_{_name}",
            pix=_pix,
            ext=_ext,
            **MOVIE,
        )
        def _dnxhr(ctx, p, outdir):
            vargs = ["-c:v", "dnxhd", "-profile:v", p["profile"]]
            return encode(ctx, p, outdir, p["ext"], vargs, p["pix"], acodec="pcm_s24le")


@recipe(
    "dnxhd-115-mov",
    "Avid DNxHD 115 (legacy fixed-bitrate 1080p23.976 flavour)",
    tags=("movie", "codec", "dnxhd", "mov", "intra"),
    needs=DNX,
    fps=23.976,
    **MOVIE,
)
def dnxhd_115(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", ["-c:v", "dnxhd", "-b:v", "115M"], "yuv422p", acodec="pcm_s24le")


@recipe(
    "dnxhr-hqx-4k-mov",
    "Avid DNxHR HQX 10-bit 4096x2160 with grain: decode throughput",
    tags=("movie", "dnxhr", "mov", "perf", "intra", "10bit"),
    needs=DNX,
    width=4096,
    height=2160,
    frames=96,
    pattern="grain",
    audio="stereo",
)
def dnxhr_hqx_4k(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", ["-c:v", "dnxhd", "-profile:v", "dnxhr_hqx"], "yuv422p10le")


@recipe(
    "cineform-mov",
    "GoPro CineForm 10-bit 4:2:2",
    tags=("movie", "codec", "cineform", "mov", "intra", "10bit"),
    needs=(FFMPEG, ffmpeg_encoder("cfhd")),
    **MOVIE,
)
def cineform(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", ["-c:v", "cfhd", "-quality", "film1"], "yuv422p10le", acodec="pcm_s24le")


@recipe(
    "cineform-rgba-mov",
    "GoPro CineForm 12-bit RGBA with alpha",
    tags=("movie", "codec", "cineform", "mov", "intra", "alpha"),
    needs=(FFMPEG, ffmpeg_encoder("cfhd")),
    **MOVIE,
)
def cineform_rgba(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", ["-c:v", "cfhd"], "gbrap12le", vf=ALPHA_RAMP, acodec="pcm_s24le")


# --------------------------------------------------------------------------------------------------------------------
# Delivery and web codecs
# --------------------------------------------------------------------------------------------------------------------


@recipe(
    "av1-mp4",
    "AV1 Main 10-bit (SVT-AV1) in MP4",
    tags=("movie", "codec", "av1", "mp4", "10bit"),
    needs=(FFMPEG, ffmpeg_encoder("libsvtav1")),
    **MOVIE,
)
def av1_mp4(ctx, p, outdir):
    vargs = ["-c:v", "libsvtav1", "-preset", "8", "-crf", "30", "-svtav1-params", "verbosity=0"]
    return encode(ctx, p, outdir, "mp4", vargs, "yuv420p10le")


@recipe(
    "av1-mkv",
    "AV1 8-bit (SVT-AV1) in Matroska",
    tags=("movie", "codec", "av1", "mkv"),
    needs=(FFMPEG, ffmpeg_encoder("libsvtav1")),
    **MOVIE,
)
def av1_mkv(ctx, p, outdir):
    return encode(ctx, p, outdir, "mkv", ["-c:v", "libsvtav1", "-preset", "8", "-crf", "30"], "yuv420p")


@recipe(
    "vp9-webm",
    "VP9 8-bit in WebM, no audio",
    tags=("movie", "codec", "vp9", "webm"),
    needs=(FFMPEG, ffmpeg_encoder("libvpx-vp9")),
    pattern="counter",
    audio="none",
)
def vp9_webm(ctx, p, outdir):
    vargs = ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-row-mt", "1", "-deadline", "realtime"]
    return encode(ctx, p, outdir, "webm", vargs, "yuv420p")


@recipe(
    "vp9-alpha-webm",
    "VP9 with alpha (yuva420p) in WebM",
    tags=("movie", "codec", "vp9", "webm", "alpha"),
    needs=(FFMPEG, ffmpeg_encoder("libvpx-vp9")),
    pattern="counter",
    audio="none",
)
def vp9_alpha(ctx, p, outdir):
    vargs = ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-deadline", "realtime", "-auto-alt-ref", "0"]
    return encode(ctx, p, outdir, "webm", vargs, "yuva420p", vf=ALPHA_RAMP)


@recipe(
    "mpeg2-ts",
    "MPEG-2 video with MP2 audio in an MPEG transport stream",
    tags=("movie", "codec", "mpeg2", "ts", "legacy"),
    needs=(FFMPEG, ffmpeg_encoder("mpeg2video"), ffmpeg_encoder("mp2")),
    **MOVIE,
)
def mpeg2_ts(ctx, p, outdir):
    return encode(ctx, p, outdir, "ts", ["-c:v", "mpeg2video", "-q:v", "3", "-g", "15"], "yuv420p")


@recipe(
    "mjpeg-avi",
    "Motion JPEG in AVI with PCM audio",
    tags=("movie", "codec", "mjpeg", "avi", "intra", "legacy"),
    needs=(FFMPEG, ffmpeg_encoder("mjpeg")),
    **MOVIE,
)
def mjpeg_avi(ctx, p, outdir):
    return encode(ctx, p, outdir, "avi", ["-c:v", "mjpeg", "-q:v", "3"], "yuvj422p")


# --------------------------------------------------------------------------------------------------------------------
# Lossless, uncompressed and archival
# --------------------------------------------------------------------------------------------------------------------


@recipe(
    "ffv1-mkv",
    "FFV1 version 3, 10-bit 4:4:4, in Matroska (archival lossless)",
    tags=("movie", "codec", "ffv1", "mkv", "lossless", "10bit"),
    needs=(FFMPEG, ffmpeg_encoder("ffv1")),
    **MOVIE,
)
def ffv1_mkv(ctx, p, outdir):
    return encode(ctx, p, outdir, "mkv", ["-c:v", "ffv1", "-level", "3", "-slices", "16"], "yuv444p10le")


@recipe(
    "ffv1-rgb16-mkv",
    "FFV1 16-bit planar RGB (scanned film archives)",
    tags=("movie", "codec", "ffv1", "mkv", "lossless", "16bit"),
    needs=(FFMPEG, ffmpeg_encoder("ffv1")),
    **MOVIE,
)
def ffv1_rgb16(ctx, p, outdir):
    return encode(ctx, p, outdir, "mkv", ["-c:v", "ffv1", "-level", "3"], "gbrp16le")


@recipe(
    "jpeg2000-mov",
    "JPEG 2000 4:4:4 in QuickTime",
    tags=("movie", "codec", "jpeg2000", "mov", "intra"),
    needs=(FFMPEG, ffmpeg_encoder("jpeg2000")),
    frames=12,
    **MOVIE,
)
def jpeg2000_mov(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", ["-c:v", "jpeg2000", "-q:v", "5"], "yuv444p", acodec="pcm_s24le")


@recipe(
    "qtrle-mov",
    "QuickTime Animation (RLE) 8-bit RGB",
    tags=("movie", "codec", "qtrle", "mov", "lossless", "legacy"),
    needs=(FFMPEG, ffmpeg_encoder("qtrle")),
    **MOVIE,
)
def qtrle(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", ["-c:v", "qtrle"], "rgb24", acodec="pcm_s16le")


@recipe(
    "qtrle-alpha-mov",
    "QuickTime Animation (RLE) with alpha",
    tags=("movie", "codec", "qtrle", "mov", "lossless", "alpha", "legacy"),
    needs=(FFMPEG, ffmpeg_encoder("qtrle")),
    **MOVIE,
)
def qtrle_alpha(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", ["-c:v", "qtrle"], "argb", vf=ALPHA_RAMP, acodec="pcm_s16le")


@recipe(
    "v210-mov",
    "Uncompressed 10-bit 4:2:2 (v210) in QuickTime",
    tags=("movie", "codec", "uncompressed", "mov", "10bit"),
    needs=(FFMPEG, ffmpeg_encoder("v210")),
    frames=12,
    **MOVIE,
)
def v210(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", ["-c:v", "v210"], "yuv422p10le", acodec="pcm_s24le")


@recipe(
    "png-in-mov",
    "PNG-compressed frames with alpha in QuickTime",
    tags=("movie", "codec", "png", "mov", "lossless", "alpha"),
    needs=(FFMPEG, ffmpeg_encoder("png")),
    frames=12,
    **MOVIE,
)
def png_in_mov(ctx, p, outdir):
    return encode(ctx, p, outdir, "mov", ["-c:v", "png"], "rgba", vf=ALPHA_RAMP, acodec="pcm_s16le")
