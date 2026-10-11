#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Synthetic picture and sound sources, expressed as ffmpeg lavfi graphs."""

from fractions import Fraction

# Picture patterns. Every source is deterministic for a given seed, so a regenerated file is pixel-identical.
#   counter   colour bars with a big frame counter; best for frame accuracy, seeking and dropped-frame checks
#   motion    testsrc2: moving shapes and a timecode-like counter; general purpose
#   bars      SMPTE HD colour bars; static, compresses to almost nothing
#   grain     motion plus per-frame noise, so codecs and PNG/EXR compressors cost what real footage costs
#   gradient  slowly moving smooth gradients; shows banding and bit-depth truncation
PATTERNS = ("counter", "motion", "bars", "grain", "gradient")


def fps_expr(fps):
    """ffmpeg rate string; 23.976, 29.97 and 59.94 become exact NTSC fractions."""
    fps = float(fps)
    for base in (24, 30, 48, 60, 120):
        ntsc = base * 1000 / 1001
        if abs(fps - ntsc) < 0.005:
            return f"{base * 1000}/1001"
    frac = Fraction(fps).limit_denominator(1001)
    return str(frac.numerator) if frac.denominator == 1 else f"{frac.numerator}/{frac.denominator}"


def video_source(pattern, width, height, fps, seed=1):
    size = f"{width}x{height}"
    rate = fps_expr(fps)
    if pattern == "counter":
        return f"testsrc=size={size}:rate={rate}:decimals=0"
    if pattern == "motion":
        return f"testsrc2=size={size}:rate={rate}"
    if pattern == "bars":
        return f"smptehdbars=size={size}:rate={rate}"
    if pattern == "grain":
        return f"testsrc2=size={size}:rate={rate},noise=alls=12:allf=t+u:all_seed={seed}"
    if pattern == "gradient":
        return f"gradients=size={size}:rate={rate}:n=4:speed=0.02:seed={seed}"
    raise ValueError(f"unknown pattern {pattern!r}; choose from {', '.join(PATTERNS)}")


# Channel layouts for generated audio. Each channel gets its own tone (440 Hz, 660 Hz, 880 Hz, ...) with a short beep
# every second, so channel order and A/V sync can both be checked by ear or with a meter.
AUDIO_LAYOUTS = {"mono": 1, "stereo": 2, "5.1": 6, "7.1": 8}


def audio_source(layout="stereo", rate=48000):
    if layout not in AUDIO_LAYOUTS:
        raise ValueError(f"unknown audio layout {layout!r}; choose from {', '.join(AUDIO_LAYOUTS)}")
    channels = AUDIO_LAYOUTS[layout]
    # Full-level tone during the first 0.1 s of each second, -20 dB otherwise.
    exprs = "|".join(f"(0.1+0.9*lt(mod(t\\,1)\\,0.1))*0.5*sin(2*PI*{440 + 220 * i}*t)" for i in range(channels))
    return f"aevalsrc=exprs={exprs}:s={rate}:c={layout}"
