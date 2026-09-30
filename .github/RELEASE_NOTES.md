# OpenUTV 2026.9

OpenUTV 2026.9 brings major feature additions: the **Supercharge FFmpeg & Third-Party Codecs Assistant**, **Portable Custom Keybindings with an interactive cheat-sheet overlay**, **Multilingual Interface Localization**, **Automatic Launch-Time Update Checking**, and comprehensive security hardening across core string handling.

---

### Supercharge FFmpeg & Professional Codecs Assistant (#35, #56)

- **FFmpeg Engine Diagnostics**: Accurately inspects the active FFmpeg configuration and distinguishes between standard GPL builds and supercharged builds (with H.265/HEVC, ProRes, AAC, libx265, and nonfree components).
- **Homebrew Shadowing Detection & 1-Click Relink**: Detects when `ffmpeg-full` is installed via Homebrew but shadowed by standard `ffmpeg` (due to `brew upgrade` overwriting symlinks) and offers a 1-click automatic relink or copyable terminal command.
- **Windows Package Managers Integration**: Detects WinGet FFmpeg Shared, Scoop, and Chocolatey installations dynamically across user profile and system paths.
- **Blackmagic RAW (BRAW) & RED (R3D) Probing**: Seamless dynamic detection for Blackmagic RAW SDK / Player across 64-bit and `Program Files (x86)` installations, and RED SDK dylibs/DLLs.
- **NewTek NDI Network Video Streaming**: Runtime detection for NDI 5 / NDI 6 Tools and runtime libraries.
- **Interactive UI & Preferences**: Accessible via **Help > Supercharge FFmpeg & Codecs...** and **Preferences > Formats**.
- **CLI / Automation Utility**: Bundled cross-platform tool (`openutv-supercharge-ffmpeg.py` with shell/batch wrappers).

---

### Custom Keybindings & Shortcuts Overlay UI (#55)

- **Portable JSON Keybindings**: Fully customizable keybindings via `~/.openutv/keybindings.json` (or platform equivalent).
- **Keyboard Shortcuts Cheat Sheet**: Interactive searchable overlay UI (**Help > Keyboard Shortcuts...** or `F1` / `?`) showing all hotkeys categorized with immediate search filtering.
- **Conflict Resolution & Validation**: Clean error handling and fallback defaults for unrecognized or ambiguous bindings.

---

### Multilingual Localization & Language Preferences (#54)

- **Multi-Language Support**: Framework for internationalization across core dialogs, menus, and preferences.
- **Language Selector**: Added Language dropdown under **Preferences > General** allowing on-the-fly UI switching with automatic locale persistence.

---

### Launch-Time Update Checker (#53)

- **Automatic Version Checks**: Background, non-blocking check against GitHub Releases on startup.
- **Update Dialog**: Notifies when a newer stable version is available, with direct links to download archives or copy Homebrew/Scoop/Chocolatey upgrade commands.
- **Snooze & Dependency Awareness**: Options to skip a version or remind later, with bundled dependency status detection.

---

### Security Hardening & Platform Fixes (#52, #57)

- **Memory & String Safety**: Replaced unsafe legacy C string functions with bounded variants across image format decoders and core libraries.
- **CI / Compiler Infrastructure**: Resolved MSVC CMake environment detection and eliminated redundant Homebrew upgrade annotations across workflow runners.
- **Package Automation**: Enhanced Chocolatey package rules and multi-platform archive packaging.

---

### Contributors

Special thanks to all contributors who worked on this release:

- @mcoliver (Michael Oliver)

---

### Installation

#### macOS (Homebrew Cask)

```bash
brew tap OpenUTV/utv https://github.com/OpenUTV/utv
brew trust openutv/utv
brew install --cask utv
```

To upgrade an existing installation:

```bash
brew upgrade --cask utv
```

#### macOS (Standalone Archive)

Download `UTV-2026.9-macOS-arm64.zip` below, extract `UTV.app`, and move it to `/Applications`.

#### Windows (Standalone Archive)

1. Download `UTV-2026.9-windows-x64.zip` below and extract the archive (e.g. to `C:\Program Files\OpenUTV` or `C:\Users\<User>\Downloads\utv-windows-x64`).
2. Launch `bin\utv.exe`.

#### Linux (Standalone Archive)

Download `UTV-2026.9-linux-x64.tar.gz` below and extract to your desired path.
