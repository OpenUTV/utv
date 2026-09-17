# OpenUTV 2026.6

OpenUTV 2026.6 delivers native cinema camera RAW decode for RED Digital Cinema (`.r3d`) and Blackmagic RAW (`.braw`), out-of-the-box OpenColorIO ACES 2.0 color management, zero-configuration NDI 6 network streaming, presentation multi-monitor playback fixes, and an upgrade to Qt 6.11.2 & PySide6 6.11.2.

---

### Native RED Digital Cinema RAW (`.r3d`) Playback & Metadata

- **Integrated RED R3D Movie Reader (`mio_r3d`)**: Native support for REDCODE RAW media files using the official RED R3D SDK without requiring third-party transcoding.
- **Hardware-Accelerated REDMetal GPU Debayering**: Instant GPU-accelerated debayering on macOS via Metal, with smooth interactive toggle between GPU and multi-threaded CPU processing.
- **Dynamic Wavelet Decode Resolution**: Real-time decode resolution switching (`Full`, `Half Premium`, `Half Good`, `Quarter`, `Eighth`, `Sixteenth`) via Image & View menus and hotkeys, featuring automatic cache invalidation and immediate frame reload.
- **Comprehensive Camera Metadata & Timecode**: Complete camera and lens metadata exposed in Media Information and Image Info boxes, including Camera Model, PIN, Firmware, Sensor Name, Serial, ISO, Shutter, Kelvins, Tint, Lens Model, Focal Length, Aperture, Focus Distance, Absolute Timecode, Edge Timecode, and Reel/Clip details.

---

### OpenColorIO & ACES 2.0 Integration

- **Bundled Official ACES 2.0 Config**: Ships with the Academy Software Foundation ACES Studio Config v2.0.0 (`studio-config-v2.0.0_aces-v1.3_ocio-v2.3.ocio`) bundled directly inside the application bundle.
- **Zero-Config Fallback**: Automatically activates and points to the bundled ACES 2.0 config when the `OCIO` environment variable is not defined on the host system.
- **Auto Setup ACES Preference**: Added a new user preference (`ocio_auto_setup_aces`) under OpenColorIO settings that automatically enables OCIO, configures the input colorspace to `ACEScg`, and aligns the display and view transforms to `sRGB`.
- **Streamlined OCIO Menu**: Ensured the OpenColorIO menu and mode controls dynamically auto-initialize and populate on startup.

---

### Native Blackmagic RAW (`.braw`) Playback

- **Dynamic BRAW Runtime Loader (`mio_braw`)**: Zero-recompile dynamic runtime loader and reader for Blackmagic RAW video media.
- **Hardware-Accelerated & CPU Decode**: Automatically leverages host GPU acceleration for high-framerate playback of `.braw` camera takes with seamless fallback to multi-threaded CPU decode.
- **Full Color & Metadata Preservation**: Reads embedded camera ISO, color temperature, tint, color gamut, and gamma curves directly into OpenUTV's imaging pipeline.

---

### NDI 6 Network Video & Multi-Monitor Presentation

- **Zero-Configuration NDI 6 Auto-Discovery**: Automatically discovers official NDI 6 runtime libraries across standard system locations on macOS (`/Library/NDI SDK for Apple/`), Windows (`C:\Program Files\NDI\NDI 6 Tools\Runtime\`, `NDI 6 SDK`), and Linux (`/usr/lib/x86_64-linux-gnu/`).
- **Fixed NDI Presentation Device Visibility**: Fixed dynamic library search paths ensuring NDI presentation output is available in display preferences on macOS and Windows out of the box.
- **Toolbar Device Switching**: Select active Display and Presentation devices directly from the main toolbar menu.
- **Presentation Playback Stability**: Fixed multi-monitor presentation viewport and timeline freezing during playback.
- **Sortable Media Information**: Added sortable column headers (Property, Value, Attribute) in the Media Information dialog for quick sorting of inspection data.

---

### Platform Modernization, Qt 6.11.2 & Windows Stability

- **Qt 6.11.2 & PySide6 6.11.2**: Upgraded UI and Python binding frameworks across all platforms, including GLSL 1.50 shader compatibility.
- **Modernized "About UTV" Inspector**: Replaced runtime dynamic Python probing with a fast, static compile-time dependency table, eliminating GIL synchronization crashes across Python 3.12–3.14.
- **Windows Executable Metadata (`utv.rc`)**: Embedded complete Windows PE version information and application icons into `utv.exe`, enabling full Windows Explorer file property details.
- **Hardened Windows Runtime**: Embedded `python314.zip`, dynamic `PYTHONHOME` detection, and strict MSVC CRT DLL distribution.

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
