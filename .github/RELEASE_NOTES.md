# OpenUTV 2026.6

OpenUTV 2026.6 brings native camera RAW decode for Blackmagic RAW (`.braw`) and RED Digital Cinema (`.r3d`), auto-detected NDI 6 network video and audio streaming, a modernized cross-platform About inspector, Windows Explorer executable metadata, and synchronized cross-platform release packaging.

---

### Native Blackmagic RAW (`.braw`) Playback

- **Dynamic BRAW Runtime Loader (`mio_braw`)**: Integrated a zero-recompile dynamic runtime loader and reader for Blackmagic RAW video media.
- **Hardware-Accelerated & CPU Decode**: Automatically leverages host GPU acceleration for high-framerate playback of `.braw` camera takes with seamless fallback to multi-threaded CPU decode.
- **Full Color & Metadata Preservation**: Reads embedded camera ISO, color temperature, tint, color gamut, and gamma curves directly into OpenUTV's imaging pipeline.

---

### Native RED Digital Cinema RAW (`.r3d`) Playback

- **Integrated RED R3D Movie Reader (`mio_r3d`)**: Added native support for REDCODE RAW media files using the official RED R3D SDK.
- **High-Performance Wavelet Decompression**: Smooth playback and inspection of RED camera footage without external transcoding.

---

### Out-of-the-Box NDI 6 Network Video Output

- **Native NDI Video Device**: Broadcast active viewport playback, synced multi-channel audio, and timeline EDL cuts directly over the local network to NDI receivers (OBS Studio, NDI Studio Monitor, vMix, TriCaster, QTAKE, etc.).
- **Zero-Configuration Auto-Discovery**: Automatically locates official NDI 6 runtime libraries across standard system locations on macOS (`/Library/NDI SDK for Apple/`), Windows (`C:\Program Files\NDI\NDI 6 Tools\Runtime\`), and Linux (`/usr/lib/x86_64-linux-gnu/`) without requiring manual environment variables.
- **Flexible Presentation Output**: Supports 8-bit RGBA, 8-bit BGRA, and 16-bit YCbCr 4:2:2 (P216) for high-dynamic-range presentation workflows.

---

### Modernized Cross-Platform "About UTV" Inspector

- **Compile-Time Dependency & License Manifest**: Replaced runtime dynamic Python probing with a fast, static dependency table generated at compile time.
- **Crash Prevention**: Completely eliminates GIL synchronization crashes across Python 3.12–3.14 on macOS, Linux, and Windows.
- **Complete Open-Source Attribution**: Accurately displays version numbers and license terms for all bundled and system libraries.

---

### Windows Executable Metadata & Alignment

- **Windows Version Resource (`utv.rc`)**: Embedded complete Windows PE version information (`CompanyName`, `FileDescription`, `FileVersion`, `ProductVersion`, and application icon) into `utv.exe`.
- **Explorer Properties Details**: Windows Explorer File Properties -> Details now accurately reports the product version, copyright, and description.
- **Strict Version Synchronization**: Aligned CMake version definitions so that Windows console `-version` output, binary metadata, and Qt GUI report matching version numbers.

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

Download `UTV-2026.6-macOS-arm64.zip` below, extract `UTV.app`, and move it to `/Applications`.

#### Windows (Standalone Archive)

1. Download `UTV-2026.6-windows-x64.zip` below and extract the archive (e.g. to `C:\Program Files\OpenUTV` or `C:\Users\<User>\Downloads\utv-windows-x64`).
2. Download and extract the runtime dependencies from [OpenUTVDeps-26.3-win64.msi](https://github.com/OpenUTV/utv-dependencies/releases/tag/v26.3) or [OpenUTVDeps 26.4](https://github.com/OpenUTV/utv-dependencies/releases/tag/v26.4).
3. Launch `bin\utv.exe`.
