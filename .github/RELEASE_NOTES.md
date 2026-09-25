# OpenUTV 2026.8

OpenUTV 2026.8 introduces out-of-the-box hardware GPU debayering for RED (R3D) media across macOS, Windows, and Linux, streamlined image settings, modern Linux toolchains with the mold linker and x86-64-v3 optimizations, session file loading fixes, and improved distribution packaging.

---

### RED (R3D) Hardware GPU Debayering & Search Paths

- **Automatic GPU Acceleration Out-of-the-Box**: OpenUTV now probes GPU acceleration capabilities across macOS (Metal/OpenCL), Windows (`OpenCL.dll`), and Linux (`libOpenCL.so.1`) on initial startup. If supported, GPU acceleration is automatically enabled by default, delivering immediate real-time playback.
- **Cross-Platform OpenCL Hardware Debayering**: Introduced a native dynamic runtime OpenCL dispatch backend (`MovieREDOpenCL.cpp` and `MovieREDGpu.cpp`) for Windows and Linux that binds directly to system OpenCL drivers without hard build-time SDK dependencies.
- **Streamlined UI**: Grouped all RED controls under **Image > RED**, featuring a top-level GPU Acceleration toggle alongside wavelet debayering resolution selections (Full, Half, Quarter, Eighth).
- **User Library Search Paths**: Added automatic lookup for RED redistributable libraries in standard user configuration directories:
  - macOS: `~/Library/Application Support/OpenUTV/RED`
  - Linux: `~/.local/share/openutv/red`
  - Windows: `%APPDATA%\OpenUTV\RED`
- **Diagnostic & Version Handshake Probing**: Probes RED library version headers and provides clear user notifications on version mismatches (such as R3D SDK 9.2.1 vs. an external 9.3.0 RED PLAYER installation).

---

### Core Stability & Session Loading

- **Session File Loading**: Fixed a crash regression when loading saved `.rv` session files (#39, #42).
- **Shader Linking**: Resolved GLSL shader linking regressions.
- **UI Reentrancy Guards**: Wrapped session manager checkbox states to eliminate Qt 6 reentrancy crashes and menu flashing.

---

### Linux & Windows Platform Modernization

- **Linux Build & Runtime Modernization**: Linux builds now utilize Homebrew dependencies, the ultra-fast `mold` linker, and `x86-64-v3` compiler optimizations for higher playback throughput (#43).
- **Windows Build & Caching**: Streamlined Windows compilation with cached MSVC environments and >99% ccache hit rates (#45).
- **Archive Structure**: Fixed package compression to prevent redundant root folder nesting when extracting macOS (`ditto`), Windows, and Linux standalone archives (#49).

---

### Contributors

Special thanks to all contributors who worked on this release:

- @mcoliver (Michael Oliver)

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

Download `UTV-2026.8-macOS-arm64.zip` below, extract `UTV.app`, and move it to `/Applications`.

#### Windows (Standalone Archive)

1. Download `UTV-2026.8-windows-x64.zip` below and extract the archive (e.g. to `C:\Program Files\OpenUTV` or `C:\Users\<User>\Downloads\utv-windows-x64`).
2. Launch `bin\utv.exe`.

#### Linux (Standalone Archive)

Download `UTV-2026.8-linux-x64.tar.gz` below and extract to your desired path.
