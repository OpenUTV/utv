#!/usr/bin/env python3
# ******************************************************************************
# Copyright (c) 2026 OpenUTV / Makai Systems
# All rights reserved.
#
# SPDX-License-Identifier: Apache-2.0
# ******************************************************************************
"""
Generate precision 10-bit and 8-bit diagnostic patterns in 16-bit TIFF and OpenEXR:
1. 10bit_banding_diagnostic: High-contrast expanded shallow-depth ramps and dither-null tests.
2. 10bit_reveal_test: Steganographic phase-inverted sub-bit messages (invisible in 8-bit).
3. 10bit_verify_test_pattern: Multi-zone optical vernier and 4-tier calibration ramps.
"""

import os
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def get_font(size):
    font_paths = [
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNS.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for p in font_paths:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size=size)
            except (OSError, ValueError):
                continue
    return ImageFont.load_default()


def to_u16(v10):
    """Scale 10-bit code value [0, 1023] to 16-bit integer [0, 65535]."""
    return np.clip(np.round(v10 * 64.0), 0, 65535).astype(np.uint16)


def export_exr(half_array, output_path, width, height):
    """Write half-float array to OpenEXR using a small self-contained C++ runner."""
    raw_path = f"/tmp/{os.path.basename(output_path)}.raw"
    half_array.tofile(raw_path)

    cpp_code = f"""
#include <OpenEXR/ImfRgbaFile.h>
#include <OpenEXR/ImfArray.h>
#include <fstream>
#include <vector>

int main() {{
    int w = {width};
    int h = {height};
    std::ifstream ifs("{raw_path}", std::ios::binary);
    std::vector<Imf::Rgba> pixels(w * h);
    ifs.read(reinterpret_cast<char*>(pixels.data()), w * h * sizeof(Imf::Rgba));
    ifs.close();

    Imf::RgbaOutputFile file("{output_path}", w, h, Imf::WRITE_RGBA);
    file.setFrameBuffer(pixels.data(), 1, w);
    file.writePixels(h);
    return 0;
}}
"""
    try:
        subprocess.run(
            [
                "clang++",
                "-O2",
                "-std=c++17",
                "-x",
                "c++",
                "-I/opt/homebrew/include",
                "-I/opt/homebrew/include/OpenEXR",
                "-I/opt/homebrew/include/Imath",
                "-L/opt/homebrew/lib",
                "-lOpenEXR",
                "-lImath",
                "-o",
                "/tmp/exr_writer_runner",
                "-",
            ],
            input=cpp_code.encode("utf-8"),
            capture_output=True,
            check=True,
        )
        subprocess.run(["/tmp/exr_writer_runner"], check=True)
        if os.path.exists(raw_path):
            os.remove(raw_path)
        print(f"Generated EXR:  {output_path}")
    except (subprocess.CalledProcessError, OSError) as e:
        print(f"Warning: Could not compile OpenEXR writer ({e}). Saved TIFF only.")


def generate_banding_diagnostic(out_dir, W=2048, H=1080):
    canvas = np.zeros((H, W), dtype=np.uint16)
    canvas[:, :] = to_u16(120)

    font_title = get_font(28)
    font_sub = get_font(18)
    font_hdr = get_font(20)

    # Zone 1: Expanded Shadow Ramp (32 to 128)
    x = np.arange(W - 80) / float(W - 80 - 1)
    shadow_10 = 32.0 + x * (128.0 - 32.0)
    shadow_8 = np.floor(shadow_10 / 4.0) * 4.0
    for y in range(120, 200):
        canvas[y, 40 : W - 40] = to_u16(shadow_10)
    for y in range(210, 290):
        canvas[y, 40 : W - 40] = to_u16(shadow_8)

    # Zone 2: Expanded Midtone Ramp (480 to 544)
    mid_10 = 480.0 + x * (544.0 - 480.0)
    mid_8 = np.floor(mid_10 / 4.0) * 4.0
    for y in range(370, 450):
        canvas[y, 40 : W - 40] = to_u16(mid_10)
    for y in range(460, 540):
        canvas[y, 40 : W - 40] = to_u16(mid_8)

    # Zone 3: Optical Null / Dither Comparison
    xx, yy = np.meshgrid(np.arange(800), np.arange(220))
    checker = (xx + yy) % 2 == 0
    dither_bg = np.where(checker, 512.0, 516.0)
    patch_mask = (xx >= 200) & (xx < 600) & (yy >= 40) & (yy < 180)
    dither_combined = np.where(patch_mask, 514.0, dither_bg)
    canvas[630:850, 100:900] = to_u16(dither_combined)

    solid_bg = np.full((220, 800), 512.0)
    solid_combined = np.where(patch_mask, 514.0, solid_bg)
    canvas[630:850, 1100:1900] = to_u16(solid_combined)

    # Zone 4: Full-Range Ramp
    full_10 = x * 1023.0
    full_8 = np.floor(full_10 / 4.0) * 4.0
    for y in range(940, 980):
        canvas[y, 40 : W - 40] = to_u16(full_10)
    for y in range(990, 1030):
        canvas[y, 40 : W - 40] = to_u16(full_8)

    im_out = Image.fromarray(canvas)
    draw = ImageDraw.Draw(im_out)

    draw.text(
        (40, 15),
        "OPENUTV 10-BIT vs 8-BIT HIGH-CONTRAST DIAGNOSTIC",
        font=font_title,
        fill=int(to_u16(950)),
    )
    draw.text(
        (40, 50),
        "Instructions: View in OpenUTV at 100% scale (press '1'). Set View -> Image Filtering -> Nearest. Turn OFF display LUT.",
        font=font_sub,
        fill=int(to_u16(750)),
    )
    draw.text(
        (40, 90),
        "ZONE 1: EXPANDED SHADOW RAMP (Code 32-128)  —  Top: 10-bit (96 steps)  |  Bottom: 8-bit (24 steps, 83px wide bands!)",
        font=font_hdr,
        fill=int(to_u16(900)),
    )
    draw.text(
        (40, 340),
        "ZONE 2: EXPANDED MIDTONE RAMP (Code 480-544)  —  Top: 10-bit (64 steps)  |  Bottom: 8-bit (16 steps, 125px wide blocks!)",
        font=font_hdr,
        fill=int(to_u16(900)),
    )
    draw.text((100, 595), "ZONE 3A: DITHER NULL TEST", font=font_hdr, fill=int(to_u16(900)))
    draw.text(
        (100, 860),
        "128/129 Checkerboard with solid 514 center patch.",
        font=font_sub,
        fill=int(to_u16(700)),
    )
    draw.text(
        (1100, 595),
        "ZONE 3B: SUB-BIT STEP REVEAL (+2 LSB)",
        font=font_hdr,
        fill=int(to_u16(900)),
    )
    draw.text(
        (1100, 860),
        "Solid 512 background with solid 514 center patch. (In 8-bit: 100% INVISIBLE)",
        font=font_sub,
        fill=int(to_u16(700)),
    )
    draw.text(
        (40, 915),
        "ZONE 4: FULL RANGE 0–1023  —  Top: 10-bit Smooth  |  Bottom: 8-bit (256 steps)",
        font=font_sub,
        fill=int(to_u16(750)),
    )

    tif_path = os.path.join(out_dir, "10bit_banding_diagnostic.tif")
    im_out.save(tif_path, format="TIFF", compression="tiff_deflate")
    print(f"Generated TIFF: {tif_path}")

    arr16 = np.array(im_out).astype(np.float32) / 65535.0
    rgba = np.zeros((H, W, 4), dtype=np.float16)
    rgba[:, :, 0] = arr16
    rgba[:, :, 1] = arr16
    rgba[:, :, 2] = arr16
    rgba[:, :, 3] = 1.0
    export_exr(rgba, os.path.join(out_dir, "10bit_banding_diagnostic.exr"), W, H)


def generate_reveal_test(out_dir, W=2048, H=1080):
    canvas = np.zeros((H, W), dtype=np.uint16)
    canvas[:, :] = to_u16(200)

    font_title = get_font(32)
    font_sub = get_font(18)
    font_hdr = get_font(20)
    font_big = get_font(48)

    def draw_grating(y_start, y_end, v0, v1, message):
        h_panel = y_end - y_start
        w_panel = W - 80
        mask_im = Image.new("L", (w_panel, h_panel), 0)
        draw_mask = ImageDraw.Draw(mask_im)
        bbox = font_big.getbbox(message)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        draw_mask.text(((w_panel - tw) // 2, (h_panel - th) // 2 + 10), message, font=font_big, fill=255)
        mask_arr = np.array(mask_im) > 128

        x_coords = np.arange(w_panel)
        phase = (x_coords // 4) % 2 == 0
        p_norm = np.where(phase, to_u16(v0), to_u16(v1))
        p_inv = np.where(phase, to_u16(v1), to_u16(v0))
        p_norm_2d = np.tile(p_norm, (h_panel, 1))
        p_inv_2d = np.tile(p_inv, (h_panel, 1))
        canvas[y_start:y_end, 40 : W - 40] = np.where(mask_arr, p_inv_2d, p_norm_2d)

    draw_grating(160, 310, 512, 516, "8-BIT VISIBLE CONTROL  [Δ = +4 LSB]")
    draw_grating(360, 510, 512, 514, "★  10-BIT DISPLAY ACTIVE  (+2 LSB)  ★")
    draw_grating(560, 710, 514, 515, "✔  10-BIT PRECISION ACTIVE  (+1 LSB)  ✔")
    draw_grating(760, 910, 65, 66, "SHADOW 10-BIT DEPTH  [CODE 65 vs 66]")

    ramp_10 = np.arange(W) / (W - 1) * 1023.0
    canvas[960:1000, :] = to_u16(ramp_10)
    canvas[1010:1050, :] = to_u16(np.floor(ramp_10 / 4.0) * 4.0)

    im_out = Image.fromarray(canvas)
    draw = ImageDraw.Draw(im_out)

    draw.text(
        (40, 20),
        "OPENUTV 10-BIT OPTICAL REVEAL DIAGNOSTIC",
        font=font_title,
        fill=int(to_u16(950)),
    )
    draw.text(
        (40, 65),
        "Instructions: Set View -> Image Filtering -> Nearest. Turn OFF Display LUT. View 1:1 scale.",
        font=font_sub,
        fill=int(to_u16(800)),
    )
    draw.text(
        (40, 95),
        "In an 8-bit pipeline: Panels 2, 3, and 4 are 100% BLANK uniform gray. On 10-bit: Embedded messages appear.",
        font=font_sub,
        fill=int(to_u16(750)),
    )
    draw.text(
        (40, 135),
        "PANEL 1: 8-BIT CONTROL REFERENCE (Δ = 4 LSB / 1 full 8-bit step: visible on all displays)",
        font=font_hdr,
        fill=int(to_u16(900)),
    )
    draw.text(
        (40, 335),
        "PANEL 2: 10-BIT VERIFICATION (Δ = 2 LSB: 100% INVISIBLE in 8-bit -> visible on 10-bit)",
        font=font_hdr,
        fill=int(to_u16(900)),
    )
    draw.text(
        (40, 535),
        "PANEL 3: 10-BIT SUB-BIT TEST (Δ = 1 LSB: 100% INVISIBLE in 8-bit -> visible on true 10-bit)",
        font=font_hdr,
        fill=int(to_u16(900)),
    )
    draw.text(
        (40, 735),
        "PANEL 4: DEEP SHADOW 10-BIT (Near-black 16/256: 100% INVISIBLE in 8-bit -> visible on 10-bit)",
        font=font_hdr,
        fill=int(to_u16(900)),
    )
    draw.text(
        (40, 935),
        "CONTINUOUS 10-BIT RAMP (TOP)  vs  8-BIT QUANTIZED RAMP (BOTTOM)",
        font=font_sub,
        fill=int(to_u16(800)),
    )

    tif_path = os.path.join(out_dir, "10bit_reveal_test.tif")
    im_out.save(tif_path, format="TIFF", compression="tiff_deflate")
    print(f"Generated TIFF: {tif_path}")

    arr16 = np.array(im_out).astype(np.float32) / 65535.0
    rgba = np.zeros((H, W, 4), dtype=np.float16)
    rgba[:, :, 0] = arr16
    rgba[:, :, 1] = arr16
    rgba[:, :, 2] = arr16
    rgba[:, :, 3] = 1.0
    export_exr(rgba, os.path.join(out_dir, "10bit_reveal_test.exr"), W, H)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    media_dir = os.path.join(script_dir, "media")
    os.makedirs(media_dir, exist_ok=True)

    print("Generating 10-bit diagnostic media in:", media_dir)
    generate_banding_diagnostic(media_dir)
    generate_reveal_test(media_dir)
    print("Done!")


if __name__ == "__main__":
    main()
