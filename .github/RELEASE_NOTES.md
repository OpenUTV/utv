# OpenUTV 2026.4

OpenUTV 2026.4 introduces major enhancements to media inspection, expanded codec and container format support, native SVG vector rendering, cross-platform GPU hardware acceleration with seamless fallback, and Windows build modernization.

---

### Dynamic Media Information & Timeline Inspector

- **Live Viewport & Playhead Tracking**: The native Qt Media Information dialog (`Ctrl+I` / `Cmd+I`) now dynamically tracks the active image or video clip in the viewport as playback traverses multi-clip timelines, EDL cuts, and frame sequences.
- **Timeline Media Dropdown**: Added an interactive **Media:** dropdown to the dialog header. Switch effortlessly between `✦ Auto (Active Viewport / Playhead)` and any individual clip loaded in the session graph (e.g. `sourceGroup000000 (shot_010.exr)`).
- **Multi-Strategy Metadata Extraction**: Robust fallback querying resolves image attributes directly from leaf source nodes and proxy headers even for clips not currently drawn to the active framebuffer.
- **Multi-Format Metadata Export**: Copy complete metadata attributes directly to the system clipboard with one click as **Formatted Text**, spreadsheet-ready **CSV**, or structured **JSON**.
- **Live Search Filtering**: Instantly search and filter through hundreds of EXIF, color mastering, audio, and container attributes in real time.

---

### Native Scalable Vector Graphics (SVG) Support

- **Built-in SVG Vector Reader (`io_svg`)**: Integrated a lightweight, zero-dependency native SVG rasterizer using NanoSVG (zlib-licensed).
- **First-Class Timeline Integration**: Open, inspect, playback, and composite vector graphics (`.svg`) directly inside OpenUTV sessions, timeline stacks, and command-line tools (`utvls`, `utvio`) without external rendering utilities.

---

### Expanded Video, Audio & Camera RAW Formats

- **Extended Video Containers**: Added native playback support for WebM (`.webm`), Ogg Video (`.ogv`), MPEG Transport Streams (`.ts`, `.mts`, `.m2ts`), DVD VOB (`.vob`), Windows Media Video (`.wmv`, `.asf`), Y4M (`.y4m`), IVF (`.ivf`), and MPEG (`.mpeg`).
- **High-Fidelity Audio Tracks**: Added playback for Free Lossless Audio Codec (`.flac`), Advanced Audio Coding (`.aac`), Opus (`.opus`), MPEG-4 Audio (`.m4a`), and Windows Media Audio (`.wma`).
- **Expanded Professional Camera RAW**: Added Panasonic Lumix RAW (`.rw2`), Sony RAW (`.sr2`), Hasselblad RAW (`.3fr`), Phase One RAW (`.iiq`), Samsung RAW (`.srw`), and Nikon RAW (`.nrw`).
- **Modern Image Formats**: Added Canon/Sony HEIF (`.hif`) and the Quite OK Image format (`.qoi`).

---

### Cross-Platform Auto-GPU Acceleration & Intelligent Fallback

- **Zero-Configuration Hardware Acceleration**: Automatically detects host GPU hardware and initializes hardware-accelerated decode/encode pipelines:
  - **macOS**: Apple VideoToolbox with native ProRes, HEVC, and H.264 acceleration.
  - **Linux**: NVIDIA NVDEC / NVENC with automatic fallback to Intel/AMD VAAPI.
  - **Windows**: NVIDIA NVDECODE / NVENC with automatic fallback to Microsoft D3D11VA and DXVA2.
- **Intelligent CPU Fallback**: Automatically and seamlessly falls back to high-performance multi-threaded CPU decoding if GPU allocation fails, VRAM limits are exceeded, or an unsupported codec profile is encountered.
- **Hardware-Accelerated Apple Silicon HEIC**: Added native Apple Silicon CoreGraphics / ImageIO hardware decoding for HEIC/HEIF with full P3 and Rec.2020 color fidelity.

---

### Legacy Subsystem Modernization & Bug Fixes

- **Image Subsystem Modernization**: Deprecated legacy redundant image plugins in favor of modern OpenImageIO 3.x with direct EXIF metadata extraction.
- **Session Manager Qt Signals**: Fixed Qt 6.11 re-entrancy issues in edit modes (`Stack`, `Switch`, `SourceGroup`) by isolating checkbox state signals during UI updates.
- **Robust Exception Handling**: Hardened Python RV command wrappers against untyped runtime exceptions across all event listeners.
- **Windows Platform & CI Overhaul**: Modernized MSVC build pipeline with Ninja, Vulkan presentation support, Python 3.14 C-extension modules, and MSI packaging.

---

### Installation

#### macOS (Homebrew Cask)

```bash
brew tap OpenUTV/utv https://github.com/OpenUTV/utv
brew install --cask utv
```

To upgrade an existing installation:

```bash
brew upgrade --cask utv
```

#### macOS (Standalone Archive)

Download `UTV-2026.4-macOS-arm64.zip` below, extract `UTV.app`, and move it to `/Applications`.
