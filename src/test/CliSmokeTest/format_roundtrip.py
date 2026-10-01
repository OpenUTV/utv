#!/usr/bin/env python3
#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Round-trip every image format utvio advertises as writable.

For each format listed by `utvio -formats` with Write capability:
  1. utvio converts a generated test image (PPM) to that format
  2. utvio converts the result back to PPM
  3. the pixels are compared against the source at known sample points

The source has distinct colored blocks in three corners, so a vertical flip, horizontal flop,
channel swap, dropped channel, or truncated file all fail. Only pure 0/1 values are used so the
check is independent of transfer functions. The test also fails if a format is advertised as
writable but cannot be written, which is how issue #59 presented.

Needs only the Python standard library.

Usage: format_roundtrip.py --bin-dir <staged bin dir> [--keep] [--only png,exr]
"""

import argparse
import os
import re
import shutil
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

from cli_common import IS_WINDOWS, find_tool, prepare_environment, run_tool

WIDTH, HEIGHT = 96, 64
BLOCK_W, BLOCK_H = 32, 16

# (x0, y0) of each block, top-left image origin, and its color.
BLOCKS = [
    ((0, 0), (1.0, 0.0, 0.0)),  # red, top-left
    ((WIDTH - BLOCK_W, 0), (0.0, 1.0, 0.0)),  # green, top-right
    ((0, HEIGHT - BLOCK_H), (0.0, 0.0, 1.0)),  # blue, bottom-left
]
BACKGROUND = (0.0, 0.0, 0.0)
BACKGROUND_SAMPLE = (WIDTH - BLOCK_W // 2, HEIGHT - BLOCK_H // 2)  # bottom-right stays black

# Lossy codecs get a wider tolerance. Everything else must match to within quantization error.
LOSSY_TOLERANCE = {
    "jpg": 0.08,
    "jpeg": 0.08,
    "webp": 0.08,
    "heic": 0.08,
    "heif": 0.08,
    "hif": 0.08,
    "avif": 0.08,
    "jxl": 0.05,
}
DEFAULT_TOLERANCE = 0.02

# Formats that are writable but not meaningful to round-trip as RGB images, with the reason.
SKIP = {
    "null": "discards output by design",
    "gto": "scene/attribute container, not a pixel format",
    "igto": "scene/attribute container, not a pixel format",
    "bw": "single-channel SGI: colour blocks collapse to grey",
    "pbm": "1-bit bitmap in PNM terms",
    "pgm": "greyscale PNM",
}

# Known platform-specific failures, tracked in an issue. They are still run and reported: a failure is
# "xfail" (does not fail the test) and an unexpected pass is "XPASS" so the entry can be removed.
KNOWN_FAILURES = {}
if sys.platform.startswith("linux"):
    # FITS written by utvio crashes (SIGSEGV) when read back on Linux.
    KNOWN_FAILURES["fits"] = "https://github.com/OpenUTV/utv/issues/67"
if IS_WINDOWS:
    KNOWN_FAILURES.update(
        {
            "heic": "https://github.com/OpenUTV/utv/issues/67",
            "heif": "https://github.com/OpenUTV/utv/issues/67",
            "hif": "https://github.com/OpenUTV/utv/issues/67",
            "fits": "https://github.com/OpenUTV/utv/issues/67",
        }
    )


def write_source_ppm(path):
    pixels = bytearray(WIDTH * HEIGHT * 3)  # black background
    for (x0, y0), color in BLOCKS:
        rgb = bytes(int(round(c * 255)) for c in color)
        for y in range(y0, y0 + BLOCK_H):
            for x in range(x0, x0 + BLOCK_W):
                offset = (y * WIDTH + x) * 3
                pixels[offset : offset + 3] = rgb
    with open(path, "wb") as f:
        f.write(f"P6\n{WIDTH} {HEIGHT}\n255\n".encode("ascii"))
        f.write(pixels)


def read_pnm(path):
    """Read binary P5/P6 PNM. Returns (width, height, channels, normalized float rows)."""
    with open(path, "rb") as f:
        data = f.read()

    tokens = []
    pos = 0
    while len(tokens) < 4:
        while data[pos : pos + 1].isspace():
            pos += 1
        if data[pos : pos + 1] == b"#":
            pos = data.index(b"\n", pos) + 1
            continue
        start = pos
        while not data[pos : pos + 1].isspace():
            pos += 1
        tokens.append(data[start:pos].decode("ascii"))
    pos += 1  # single whitespace after maxval

    magic, width, height, maxval = tokens[0], int(tokens[1]), int(tokens[2]), int(tokens[3])
    if magic not in ("P5", "P6"):
        raise ValueError(f"unsupported PNM type {magic}")
    channels = 3 if magic == "P6" else 1
    sample_bytes = 2 if maxval > 255 else 1
    body = data[pos:]
    expected = width * height * channels * sample_bytes
    if len(body) < expected:
        raise ValueError(f"truncated PNM: {len(body)} of {expected} bytes")

    if sample_bytes == 1:
        samples = [v / maxval for v in body[:expected]]
    else:
        samples = [int.from_bytes(body[i : i + 2], "big") / maxval for i in range(0, expected, 2)]
    return width, height, channels, samples


def sample(img, x, y):
    width, _height, channels, samples = img
    offset = (y * width + x) * channels
    values = samples[offset : offset + channels]
    return tuple(values) * 3 if channels == 1 else tuple(values)


def check_pixels(img, tolerance):
    width, height, _channels, _samples = img
    if (width, height) != (WIDTH, HEIGHT):
        return f"size {width}x{height}, expected {WIDTH}x{HEIGHT}"

    points = [((x0 + BLOCK_W // 2, y0 + BLOCK_H // 2), color) for (x0, y0), color in BLOCKS]
    points.append((BACKGROUND_SAMPLE, BACKGROUND))
    for (x, y), expected in points:
        got = sample(img, x, y)
        if any(abs(g - e) > tolerance for g, e in zip(got, expected)):
            got_str = ", ".join(f"{v:.3f}" for v in got)
            return f"pixel ({x},{y}) is ({got_str}), expected {expected} (tolerance {tolerance})"
    return None


def writable_image_formats(utvio, env, timeout):
    result = run_tool([utvio, "-formats"], env, timeout)
    if result.timed_out or result.returncode != 0:
        raise RuntimeError(f"utvio -formats failed (exit {result.returncode}):\n{result.output}")

    formats = []
    for match in re.finditer(r'^format "([^"]+)" - .*\(([^)]*)\)\s*$', result.output, re.MULTILINE):
        ext, caps = match.group(1), [c.strip() for c in match.group(2).split(",")]
        # Movie/audio plugins advertise Audio*/Attribute* capabilities; image plugins only Read/Write.
        if "Write" in caps and not any(c.startswith(("Audio", "Attribute")) for c in caps):
            if ext not in formats:
                formats.append(ext)
    return formats


def roundtrip(utvio, env, timeout, workdir, source, ext):
    encoded = os.path.join(workdir, f"t.{ext}")
    decoded = os.path.join(workdir, f"t.{ext}.back.ppm")

    result = run_tool([utvio, "-err-to-out", source, "-o", encoded], env, timeout)
    if result.timed_out or result.returncode != 0 or not os.path.isfile(encoded):
        return f"write failed (exit {result.returncode}, timed_out={result.timed_out}): {last_error(result.output)}"

    result = run_tool([utvio, "-err-to-out", encoded, "-o", decoded], env, timeout)
    if result.timed_out or result.returncode != 0 or not os.path.isfile(decoded):
        return f"read back failed (exit {result.returncode}, timed_out={result.timed_out}): {last_error(result.output)}"

    try:
        img = read_pnm(decoded)
    except (ValueError, OSError) as exc:
        return f"could not parse decoded PPM: {exc}"
    return check_pixels(img, LOSSY_TOLERANCE.get(ext, DEFAULT_TOLERANCE))


def last_error(output):
    lines = output.strip().splitlines()
    # X11 protocol errors span several lines; the first one names the error and request.
    x_errors = [line for line in lines if "X Error" in line]
    if x_errors:
        return x_errors[0].strip()
    errors = [line for line in lines if "ERROR" in line]
    return errors[-1].strip() if errors else (lines or ["(no output)"])[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bin-dir", required=True, help="Staged application bin directory")
    parser.add_argument("--timeout", type=int, default=120, help="Per-conversion timeout in seconds")
    parser.add_argument("--only", help="Comma-separated list of extensions to test")
    parser.add_argument("--keep", action="store_true", help="Keep the working directory for inspection")
    args = parser.parse_args()

    utvio = find_tool(args.bin_dir, "utvio")
    if not utvio:
        print(f"FAIL: utvio not found in {args.bin_dir}")
        return 1

    env = prepare_environment()
    formats = writable_image_formats(utvio, env, args.timeout)
    if args.only:
        wanted = args.only.split(",")
        formats = [f for f in formats if f in wanted]
    if not formats:
        print("FAIL: no writable image formats found")
        return 1

    workdir = tempfile.mkdtemp(prefix="utv_format_roundtrip_")
    source = os.path.join(workdir, "source.ppm")
    write_source_ppm(source)

    tested = [f for f in formats if f not in SKIP]
    for ext in formats:
        if ext in SKIP:
            print(f"skip {ext}: {SKIP[ext]}")

    with ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 2)) as pool:
        results = list(pool.map(lambda e: (e, roundtrip(utvio, env, args.timeout, workdir, source, e)), tested))

    failures = []
    for ext, problem in results:
        known = KNOWN_FAILURES.get(ext)
        if problem and known:
            print(f"xfail {ext}: {problem} (known: {known})")
        elif problem:
            failures.append((ext, problem))
            print(f"FAIL {ext}: {problem}")
        elif known:
            print(f"XPASS {ext}: passes now, remove it from KNOWN_FAILURES ({known})")
        else:
            print(f"ok   {ext}")

    if args.keep:
        print(f"\nWorking directory kept: {workdir}")
    else:
        shutil.rmtree(workdir, ignore_errors=True)

    if failures:
        print(f"\n{len(failures)} of {len(tested)} formats failed the round trip")
        return 1
    xfails = sum(1 for ext, problem in results if problem and ext in KNOWN_FAILURES)
    passed = len(tested) - xfails
    suffix = f" ({xfails} known failures, see above)" if xfails else ""
    print(f"\n{passed} of {len(tested)} writable image formats round-tripped{suffix}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
