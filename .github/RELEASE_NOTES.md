# OpenUTV 2026.2

### Initial Release Community Callout

- **Community Issue Tracking**: Added a prominent callout to the community to stress-test UTV and report broken codecs, visual glitches, performance bottlenecks, unexpected behaviors, and feature requests via GitHub Issues.

### Hardware Decoding & Video Playback

- **Expanded VideoToolbox Hardware Acceleration**: Accelerated decoding via Apple Silicon VideoToolbox now supports **H.264**, **HEVC (H.265)**, **Apple ProRes**, **VP9**, and **AV1** out of the box.
- **ProRes 422 Green Screen Fix**: Resolved a 10-bit VideoToolbox decoding bug where ProRes 422 files (`P210LE` semi-planar) decoded with a solid green tint due to an unshifted 6-bit shift offset and incorrect plane line-stride calculations.
- **Runtime Silicon Capability Detection**: Integrated dynamic `VTIsHardwareDecodeSupported()` queries per codec so unsupported hardware formats seamlessly fall back to CPU software decoding.
- **Zero-Crash Software Fallback**: Automatically and gracefully falls back to multi-threaded CPU software decoding if hardware decoding encounters stream limits or decoder allocation errors.
- **Hardware Decoding Preferences & Controls**:
  - Added a new **Hardware Video Decoding** preference under **Preferences -> Caching** (`Auto (All Supported Codecs)`, `ProRes Only`, `Disabled (Software CPU)`).
  - Added pipeline environment variable control via `OPENUTV_HWACCEL` / `UTV_HWACCEL` (`all`, `prores`, `none`).

### Intelligent Caching & Memory Architecture

- **Auto Smart Media Caching**: Introduced an intelligent auto-caching engine (`Auto (Smart Media Detection)`) in Preferences and CLI (`-ac`):
  - **Fast Intra-Frame Video** (Apple ProRes, ProRes RAW, Avid DNxHR/DNxHD, JPEG 2000, Motion JPEG): Automatically routes to **No Caching** (`NeverCache`) for instant real-time playback without RAM saturation.
  - **Image Sequences** (EXR, DPX, TIFF, etc.) & **Inter-Frame Video** (MPEG-1/2, H.264, HEVC, AV1, VP9): Automatically engages **Look-Ahead Cache** (`BufferCache`) to ensure smooth playback and prevent audio clock drops.
  - Emits informative console logs identifying the media format and the selected caching strategy.
- **Zero-Wait Buffer Overrun (`0.0s`)**: Set default Look-Ahead wait time to `0.0s` across preferences and CLI options, allowing playback to decode on-the-fly when cache buffers are overrun rather than pausing.
- **Hardware Memory Protection**: Query physical RAM on Apple Silicon dynamically using `sysctl HW_MEMSIZE` and clamp cache allocations to a safe ceiling of 85% of physical memory to prevent system freezes.
- **Playback Stall Notifications**: Added rate-limited console notices with actionable troubleshooting tips if buffer starvation ever interrupts playback.
- **Intra-Frame Seek Optimization**: Cleaned FFmpeg slow random access classifications, ensuring NLE codecs are recognized as fast random access and eliminating erroneous slow access flags.

### Application Versioning & Metadata Alignment

- **Dynamic Release Version Resolution**: Replaced the legacy hardcoded `2026.9.10` placeholder in `CMakeLists.txt` with dynamic Git tag resolution matching semantic releases (e.g. `2026.2`).
- **Clean Version Display**: Updated the About dialog, CLI tools (`-version`), and macOS bundle metadata (`CFBundleShortVersionString`, `CFBundleVersion`) to cleanly display `2026.2` without appending redundant patch numbers when the patch level is 0.

### Bundled Python Runtime & Packaging

- **Self-Contained Site-Packages**: Bundled all runtime Python dependencies (`opentimelineio`, `six`, `numpy`, `PyOpenGL`, `requests`, `certifi`, `pydantic`, etc.) directly into `UTV.app/Contents/lib/python3.14/site-packages/`.
- **Standalone Execution**: Launching `UTV.app` from Finder or standalone archives functions out of the box with full plugin support without requiring local `pip` installs or virtual environments.
- **Clean Release Packaging**: Excluded macOS extended metadata / AppleDouble `._*` dot-files from release archives to ensure clean extraction and reliable plugin discovery.
- **Path Discovery**: Hardened `rv_commands_setup.py`, `DarwinBundle.mm`, and `QTBundle.cpp` to discover and prioritize bundled site-packages with fallbacks for Homebrew and developer virtualenvs.
- **Python 3 Modernization**: Converted `source_setup.py`, `retimeExportHook.py`, and `otio_writer.py` to use standard library `urllib.parse` and `math.isclose`.

### Branding, Copyright & Metadata

- **Downstream License Compliance**: Updated macOS bundle metadata (`Info.plist`) with explicit OpenUTV ownership while honoring historical attribution: `Copyright © 2026 OpenUTV Contributors. Portions Copyright 2022-2023 Autodesk, Inc., and 2001-2022 Tweak Software.`
- **Bundle Identifiers**: Modernized bundle identifiers across all targets from `com.autodesk` to `com.OpenUTV`.

### Code Signing & Apple Notarization

- **Apple Notarization & Stapled Tickets**: Fully signed with Developer ID Application certificate and notarized by Apple with stapled tickets.
- **Hardened Runtime**: Built and codesigned with macOS Hardened Runtime, valid entitlements, and verified signature seals. Eliminates Gatekeeper warnings.

### macOS Launcher & Dependency Validation

- **Native Objective-C Launcher (`UTVLauncher.mm`)**: Replaced direct bundle executable entry with a native launcher linking only to system Cocoa frameworks to prevent `dyld` termination on missing dylibs.
- **Dependency Validation**: Verifies required Homebrew packages (`qt`, `python@3.14`, `ffmpeg-full`, `opencolorio`, `openexr`, `imath`, etc.) prior to binary execution, providing a native macOS dialog to install missing components.

### Display & Color Pipeline

- **10-Bit Color Pipeline**: Native 10-bit Metal presentation pipeline, extended sRGB color space, and EDR calibration for Apple Liquid Retina XDR and HDR displays (plus 10-bit Vulkan surfaces on Linux and Windows).
- **10-Bit Diagnostics**: Added depth verification tool and test pattern generator (`tools/diagnostics/10bit/`).
- **Metal Viewport Hardening**: Fixed checkerboard flicker during mouse tracking and cursor motion in `QtMetalVideoDevice`.

### Media Codecs & Playback

- **Native PDF Document Support**: Added multi-page reader powered by macOS CoreGraphics with automatic page cropping.
- **Apple ProRes RAW**: Added 16-bit half-float (`64RGBAHalf`) decoding via AVFoundation and FFmpeg.
- **MPEG & Inter-Frame Playback**: Resolved stutter and repetitive header error logging in `MovieFFMpeg`.
- **JPEG 2000 & HTJ2K**: Support via OpenJPEG and FFmpeg.

### Qt 6.11 Compatibility & Upstream Ports

- **Qt 6.11 Stability**: Resolved Session Manager reentrancy crashes during model updates.
- **Ported OpenRV PR 1350**: Resolved EXR + WAV audio/video playback synchronization stutter.
- **Ported OpenRV PR 1321**: Hardened display screen selection against invalid monitor indices.
- **Ported OpenRV PR 1393**: Bound missing `QAction` / `QToolButton` APIs and modernized SignalSpy for Qt 6.11.

---

### Installation

#### macOS (Homebrew Cask)

```bash
brew tap OpenUTV/utv https://github.com/OpenUTV/utv
brew install --cask utv
```

#### macOS (Standalone Archive)

Download `UTV-2026.2-macOS-arm64.zip` below, extract `UTV.app`, and move it to `/Applications`.
