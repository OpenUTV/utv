# 10-Bit Display Presentation Diagnostics & Test Suite

This directory contains diagnostic tools, scripts, and precision test media designed to verify and troubleshoot 10-bit display pipelines, Core Animation presentation, and bit-depth quantization in OpenUTV.

---

## 1. Directory Structure

```text
tools/diagnostics/10bit/
├── README.md                          # This documentation
├── check_macos_display_depth.py       # Queries macOS display bit depth, color space, and EDR headroom
├── generate_10bit_test_patterns.py    # Python generator script for TIFF (16-bit) and OpenEXR patterns
└── media/                             # Reference test media
    ├── 10bit_banding_diagnostic.exr
    ├── 10bit_banding_diagnostic.tif
    ├── 10bit_reveal_test.exr
    └── 10bit_reveal_test.tif
```

---

## 2. Hardware Realities: 8-Bit + FRC vs True 10-Bit Displays

When testing 10-bit presentation on macOS, it is critical to understand the distinction between physical panel capabilities:

### Built-in MacBook Liquid Retina Displays (non-XDR)

- Most built-in MacBook screens (e.g. MacBook Air, 13"/15" MacBook models) feature **8-bit IPS panels**.
- These panels physically have 8-bit DACs (256 physical voltage states per subpixel).
- macOS achieves wide color (Display P3) and 10-bit simulation via **hardware temporal dithering (FRC - Frame Rate Control)**.
- macOS reports `NSBitsPerSample: 8` and `maximumExtendedDynamicRangeColorComponentValue: 1.00`.
- Because macOS automatically dithers both 8-bit and 10-bit content at the hardware display controller level, subtle 1-bit or 2-bit code value differences ($\Delta \le 0.39\%$) are blended smoothly by the display controller.

### External 10-Bit Reference Displays & Liquid Retina XDR

- Professional grading monitors (Apple Pro Display XDR, Eizo ColorEdge, ASUS ProArt, Sony TRIMASTER, Dell PremierColor) connected via Thunderbolt, DisplayPort, or HDMI 2.1 feature **true 10-bit physical panels**.
- MacBook Pro models with **Liquid Retina XDR** (mini-LED backlights) support native extended dynamic range (EDR $\ge 2.0$).
- On these monitors, macOS reports `NSBitsPerSample: 10`. The 10-bit Metal pipeline drives the hardware DACs directly without 8-bit window truncation.

### To Query Your Connected Display(s)

```bash
python3 tools/diagnostics/10bit/check_macos_display_depth.py
```

---

## 3. OpenUTV 10-Bit Metal Architecture

OpenUTV presents 10-bit deep color on macOS through the following pipeline:

1. **Floating-Point Render FBO**: `IPCore::ImageRenderer` evaluates color nodes, OCIO transforms, and shaders inside a 16-bit half-float FBO (`GL_RGBA16F_ARB`).
2. **Zero-Copy 10-Bit Blit**: `QTMetalVideoDevice::syncBuffers` executes a GPU `glBlitFramebufferEXT` from `GL_RGBA16F_ARB` into an `IOSurface`-backed `GL_RGB10_A2` texture (`kCVPixelFormatType_ARGB2101010LEPacked`).
3. **Core Animation EDR Scanout**:
   - `MetalView.mm` sets `layer.wantsExtendedDynamicRangeContent = YES;`.
   - The native `NSWindow` is opted into `[NSColorSpace extendedSRGBColorSpace]`.
   - The presentation `IOSurface` is tagged with `kCVImageBufferCGColorSpaceKey = sRGB`.
   - This prevents macOS Window Server from truncating the layer to standard 8-bit SDR during window composition.

---

## 4. Test Media Overview

### `10bit_banding_diagnostic.exr` / `.tif`

- **Zone 1 (Expanded Shadow Ramp)**: Spans only code values 32 to 128 across 2000 pixels.
  - *8-bit*: 24 chunky steps (83 pixels wide each).
  - *10-bit*: 96 steps (4× smoother).
- **Zone 2 (Expanded Midtone Ramp)**: Spans code values 480 to 544 across 2000 pixels.
  - *8-bit*: 16 massive steps (125 pixels wide each, over 1.5 inches wide on screen).
  - *10-bit*: 64 steps.
- **Zone 3A (Dither Null Test)**: Alternating 128/129 1-pixel checkerboard with a solid 10-bit 514 center patch.
- **Zone 3B (Sub-Bit Step Reveal)**: Solid 10-bit 512 background with a solid 10-bit 514 center patch. In an 8-bit pipeline, both truncate to 128 (100% invisible).
- **Zone 4 (Full Range 0–1023)**: Full-range continuous 10-bit ramp vs quantized 256-level 8-bit ramp.

### `10bit_reveal_test.exr` / `.tif`

- Uses **spatial grating phase inversion** to embed diagnostic messages:
  - Panel 1: `8-BIT VISIBLE CONTROL` ($\Delta = +4$ LSB / 1 full 8-bit step). Visible on all displays.
  - Panel 2: `10-BIT DISPLAY ACTIVE` ($\Delta = +2$ LSB). Completely invisible in 8-bit; appears in 10-bit.
  - Panel 3: `10-BIT PRECISION ACTIVE` ($\Delta = +1$ LSB).
  - Panel 4: `SHADOW 10-BIT DEPTH` (Codes 65 vs 66 in near-black).

---

## 5. How to Test in OpenUTV

To evaluate bit-depth without distortion from viewport scaling or display LUTs:

1. **Launch OpenUTV with the test image**:

   ```bash
   _build/stage/app/UTV.app/Contents/MacOS/UTV tools/diagnostics/10bit/media/10bit_banding_diagnostic.exr
   ```

2. **Crucial Viewport Settings**:
   - **Texture Filtering**: Set **`View -> Image Filtering -> Nearest`** (or press `Shift + F`).
     - *Why*: OpenUTV defaults to `Linear` (bilinear) filtering. When fitting an image to the window, bilinear filtering linearly interpolates adjacent pixels, smoothing out the quantized 8-bit steps. `Nearest` displays the true discrete step boundaries.
   - **1:1 Scale**: Press **`1`** on the keyboard to lock the zoom at 100% 1:1 pixel scale.
   - **Display LUT**: Click the **`sRGB`** toolbar button to toggle it **OFF** (or set `View -> Linear to display correction -> No Correction` and `Color -> File nonlinear to linear conversion -> No Conversion`).

3. **Compare Metal (10-Bit) vs OpenGL (8-Bit)**:
   - **Metal 10-Bit Presentation (Default)**:

     ```bash
     _build/stage/app/UTV.app/Contents/MacOS/UTV tools/diagnostics/10bit/media/10bit_banding_diagnostic.exr
     ```

   - **Forced 8-Bit OpenGL Legacy Backend**:

     ```bash
     RV_DISABLE_METAL_VIEW=1 _build/stage/app/UTV.app/Contents/MacOS/UTV tools/diagnostics/10bit/media/10bit_banding_diagnostic.exr
     ```

---

## 6. Re-generating Test Media

To regenerate or customize the test patterns:

```bash
python3 tools/diagnostics/10bit/generate_10bit_test_patterns.py
```

Outputs are automatically written to `tools/diagnostics/10bit/media/`.
