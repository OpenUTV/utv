# OpenUTV 2026.7

OpenUTV 2026.7 brings native OS file dialogs enabled by default, directory and folder-based media sequence loading, a brand new native C++ trampoline launcher for Windows with automatic hardware and software OpenGL fallback detection, hardened startup logging against crashes on customized user profiles, and bundled Windows diagnostic and update tools.

---

### Native OS File Dialogs & Directory Loading

- **Native File Dialogs by Default**: True native OS dialogs (macOS Finder / Windows Explorer / Linux desktop portal) are now enabled by default for a seamless, platform-consistent file browsing experience.
- **File Dialog Preference**: Added a user preference under **Preferences > General > Use Native File Dialog** allowing users to switch between native OS dialogs and Qt dialogs at any time.
- **Open Directory Support**: Added a dedicated **File > Open Directory...** menu action (`Ctrl+Shift+O` / `Cmd+Shift+O`) to quickly load entire media folders.
- **Multi-File and Folder Selection**: The open dialog now supports selecting directories directly; OpenUTV automatically unpacks and loads all image sequences and media files contained within.
- **Unified Sequence Unpacking**: Replaced fragmented directory traversal with a unified, robust sequence discovery engine.

---

### Windows Native Trampoline Launcher & Unbundled Architecture

- **Native Trampoline Launcher (`utv.exe`)**: Replaced legacy shell launch scripts with a fast, high-performance native C++ launcher executable that coordinates environment initialization and application startup.
- **Automatic OpenGL Capability Detection**: Probes the host system's OpenGL hardware profile before launching the application. If OpenGL support is below 2.1 or using software GDI Generic renderers, it automatically enables Mesa software rasterization (`opengl32sw.dll`) for reliable fallback.
- **Unified Desktop OpenGL**: Configures `QT_OPENGL=desktop` to ensure Qt and OpenUTV's internal viewport share the same desktop OpenGL context.
- **Comprehensive Dependency Discovery**: Automatically discovers external runtime dependencies across `C:\Program Files\OpenUTVDeps*`, Windows registry uninstall entries, `OPENUTV_DEPS_ROOT`, and PySide6 Qt runtimes.

---

### Startup Stability & Hardened Logging

- **Pre-Created Log Paths**: Resolves startup crashes when initializing log files by pre-creating `%APPDATA%\OpenUTV\Logs` using Qt path utilities before file sinks are opened.
- **Guarded Log Initialization**: Wrapped `spdlog` file helper sinks in structured exception handlers with graceful fallback to stderr/console output, preventing unhandled exceptions on systems with roaming profiles, non-ASCII paths, or restricted permissions.
- **Null Safety Guards**: Hardened all internal log dispatch points to safely operate even if the logging sink fails to initialize.

---

### Windows Diagnostics & Tools

- **Diagnostics Packager**: Deployed `openutv-diagnostics.bat` into the Windows release distribution, enabling 1-click collection of system info, graphics driver details, and crash logs for issue reporting.
- **Update Checker**: Deployed `openutv-check-updates.bat` for fast command-line GitHub release checks on Windows.
- **Bundled PyOpenColorIO**: Included PyOpenColorIO packages within the Windows distribution for out-of-the-box OpenColorIO 2.5 Python scripting.
- **CLI Options**: Restored the `-workItemThreads` command-line argument in CLI option parsing.

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

Download `UTV-2026.7-macOS-arm64.zip` below, extract `UTV.app`, and move it to `/Applications`.

#### Windows (Standalone Archive)

1. Download `UTV-2026.7-windows-x64.zip` below and extract the archive (e.g. to `C:\Program Files\OpenUTV` or `C:\Users\<User>\Downloads\utv-windows-x64`).
2. Download and extract the runtime dependencies from [OpenUTVDeps 26.5](https://github.com/OpenUTV/utv-dependencies/releases/tag/v26.5) or install via the MSI package.
3. Launch `bin\utv.exe`.
