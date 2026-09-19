# OpenUTV Developer & Agent Guide (`AGENTS.md`)

This document serves as an operational manual, architectural reference, and workflow guide for AI coding assistants and developers working on the OpenUTV codebase.

---

## 1. Development Environment & Commit Rules

### 1.1 GPG Signed Commits

All commits to the OpenUTV repository **must be GPG signed** (`git commit -S`).

- Local config key: `user.signingkey` is configured with an Ed25519 key (e.g. `Michael Oliver <mcoliver@gmail.com>`).
- Global/repo setting: `commit.gpgsign = true`.
- To verify a commit: `git log -1 --show-signature`.

### 1.2 Pre-Commit Hooks

Pre-commit checks are configured via `.pre-commit-config.yaml`:

- **`cmake-format`**: Enforces CMake syntax and indentation.
- **`ruff-check`** & **`ruff-format`**: Python linting and formatting.
- **`clang-format`**: C/C++ formatting according to `.clang-format`.
- **`markdownlint`**: Markdown style rules according to `.markdownlint.yaml`.

#### Running Pre-Commit

- **Always run on staged files**:

  ```bash
  git add <modified-files>
  pre-commit run
  ```

- **Windows Caveat with Symlinks**:
  On Windows, git checkouts with `core.symlinks = false` check out repository symlinks (such as `src/lib/mu/MuQt6/qt2mu.py` or other Mu scripts) as plaintext pointer files.
  - Avoid running `pre-commit run --all-files` directly on Windows, as Ruff will parse these symlink text files as invalid Python scripts and attempt to reformat them.
  - Run `pre-commit run` only on staged files before committing.

---

## 2. Architecture: Launching & Runtime Initialization

### 2.1 Native Trampoline Launcher on Windows (`utv.exe`)

On Windows, launching `utv-bin.exe` directly often fails due to missing environment variables, DLL search paths, and dependency locations. OpenUTV uses a native C++ launcher (`src/bin/apps/rv/UTVLauncherWin.cpp`) compiled as `utv.exe`.

The launcher performs the following:

1. **Dependency Auto-Discovery**:
   - Searches `C:\Program Files\OpenUTVDeps*` and `%OPENUTV_DEPS_ROOT%`.
   - Inspects the Windows Registry under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OpenUTVDeps*` and `HKCU`.
   - Discovers PySide6's Qt distribution and bundled Python environments.
2. **DLL Search Path Management**:
   - Calls `SetDllDirectoryW` and `AddDllDirectory()` with `LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_USER_DIRS`.
   - Injects dependency paths (`bin/`, `installed/x64-windows/bin/`, `tools/python3/`, etc.).
3. **Environment Setup**:
   - Sets `PATH`, `PYTHONHOME`, `QT_PLUGIN_PATH`, `QTWEBENGINEPROCESS_PATH`, and `QTWEBENGINE_RESOURCES_PATH`.

### 2.2 OpenGL Hardware vs. Software Fallback

- OpenUTV probes the host system's GPU capabilities before launching `utv-bin.exe`:
  - Creates a temporary hidden 1x1 window, sets up a pixel format, and creates a WGL context.
  - Queries `glGetString(GL_RENDERER)` and `glGetString(GL_VERSION)`.
  - If OpenGL version is `<= 2.1` or the renderer contains `"GDI Generic"` (indicating unaccelerated Microsoft Basic Display Adapter), it automatically activates Mesa software OpenGL fallback (`opengl32sw.dll`).

### 2.3 OpenGL Context Unification (`QT_OPENGL=desktop`)
>
> [!IMPORTANT]
> **Never set `QT_OPENGL=software` on Windows.**
> When `QT_OPENGL=software` is set:
>
> 1. Qt's Windows platform plugin (`qwindows.dll`) explicitly loads `opengl32sw.dll`.
> 2. OpenUTV (`utv-bin.exe`) and GLEW link against `opengl32.dll`.
> 3. If Mesa llvmpipe is placed as `opengl32.dll`, two separate instances of Mesa run concurrently inside the same process. This causes context sharing failures, broken texture IDs, and a blank/black viewport.
>
> **The Solution**: Keep `QT_OPENGL=desktop` and deploy Mesa llvmpipe as `opengl32.dll` in the application directory. Both Qt and OpenUTV resolve OpenGL from the identical DLL instance, ensuring context and framebuffer sharing function correctly.

### 2.4 Hardened Logging Subsystem (`FileLogger.cpp`)

- OpenUTV uses `spdlog` for file and console logging (`src/lib/base/TwkUtil/FileLogger.cpp`).
- **Crash Prevention**:
  - `spdlog::basic_logger_mt` / `spdlog::details::file_helper::open` throws an unhandled `spdlog_ex` if the target directory does not exist or if user paths contain non-ASCII characters or network redirections.
  - Always pre-create the log directory (`%APPDATA%/OpenUTV/Logs` on Windows) using `QDir().mkpath()` *before* initializing the sink.
  - Always wrap `spdlog` creation in a `try / catch (const std::exception& e)` block, falling back gracefully to console/stderr.
  - Null-guard every call on `m_logger` (`if (m_logger) m_logger->info(...)`).

### 2.5 Native File Dialogs & Sequence Loading

- OpenUTV defaults to native OS file dialogs (`useNativeFileDialog = 1` in `Options.cpp` and fallback `true` in `MuUICommands.cpp`).
  - macOS uses `NSOpenPanel` (Finder).
  - Windows uses `IFileOpenDialog` (Windows Explorer).
- **Directory Loading**:
  - Added **File > Open Directory...** (`Ctrl+Shift+O` / `Cmd+Shift+O`).
  - Selecting directories in the file picker invokes unified sequence unpacking to load all image sequences and media within the folder recursively.

### 2.6 macOS Notarization, Hardened Runtime & Codesigning Order

- When Python wheels are installed via `requirements.txt` into `UTV.app/Contents/lib/python3.14/site-packages`, packages such as `opencolorio` bundle standalone CLI binaries under `PyOpenColorIO/bin/` (e.g. `ociocpuinfo`, `ocioconvert`).
- **Apple Notarization Requirement**: Apple's Notary Service scans *every* Mach-O binary in the entire `.zip` archive. Unsigned CLI binaries or binaries missing a secure timestamp / hardened runtime will cause notarization rejection.
  - OpenUTV only requires the in-process Python C-extension (`import PyOpenColorIO as OCIO`); the standalone CLI binaries are unnecessary inside the GUI application bundle.
  - `build.sh` and `build-and-release.yml` explicitly purge `bin/` directories inside `Contents/lib/**/site-packages/`.
- **Hardened Runtime & Library Validation (`com.apple.security.cs.disable-library-validation`)**:
  - OpenUTV on macOS dynamically links against third-party and Homebrew libraries (such as Qt 6 in `/opt/homebrew`).
  - Under Hardened Runtime (`--options runtime`), macOS dyld will reject loading non-Apple dylibs unless the process holds the `com.apple.security.cs.disable-library-validation` entitlement (defined in `src/bin/nsapps/UTV/entitlements.plist`).
  - **Critical Signing Rule**: ALL executables in `Contents/MacOS` (especially `UTV-bin` and the `UTV` launcher) MUST be signed with `--entitlements "$ENTITLEMENTS"`.
  - Any generic sweep to sign remaining Mach-O binaries in the bundle MUST prune `$APP_PATH/Contents/MacOS` (`find ... -path "$APP_PATH/Contents/MacOS" -prune -o ...`) so that `codesign --force` without entitlements NEVER touches or overwrites `UTV-bin`. Overwriting `UTV-bin` without entitlements immediately breaks dyld library loading on user machines with `EXC_CRASH (SIGABRT) / code signature not valid for use in process`.
- **Strict Signing Order**:
  1. Helper apps (`Contents/Helpers/*.app`)
  2. Frameworks (`Contents/Frameworks/*.framework`)
  3. Dynamic libraries and Python C-extensions (`*.dylib`, `*.so`)
  4. PlugIns subcomponents (`Contents/PlugIns`)
  5. Any remaining Mach-O binaries in `Contents` *outside* `Contents/MacOS`
  6. All executables in `Contents/MacOS` (`UTV-bin`, `UTV`) WITH `--entitlements "$ENTITLEMENTS"`
  7. Outer bundle (`UTV.app`) WITH `--entitlements "$ENTITLEMENTS"`

---

## 3. Versioning & Release Workflow

### 3.1 Version Definition

OpenUTV follows calendar versioning: `YYYY.MINOR.REVISION` (e.g. `2026.7.0`).

- The canonical base version is defined in root [`CMakeLists.txt`](CMakeLists.txt):

  ```cmake
  SET(RV_MAJOR_VERSION "2026" CACHE STRING "RV's version major")
  SET(RV_MINOR_VERSION "7" CACHE STRING "RV's version minor")
  SET(RV_REVISION_NUMBER "0" CACHE STRING "RV's revision number")
  SET(RV_VERSION_YEAR "2026" CACHE STRING "RV's year of release.")
  ```

- Command-line build scripts pass `-DRV_MAJOR_VERSION=...`, `-DRV_MINOR_VERSION=...`, `-DRV_VERSION_EXPLICIT=ON`.

### 3.2 What to Update for a New Release

When preparing a new release (e.g. bumping from `2026.6` to `2026.7`):

1. **`CMakeLists.txt`**: Increment `RV_MINOR_VERSION`.
2. **`README.md`**: Update feature comparison table header (e.g. `OpenUTV (2026.7+)`).
3. **`.github/RELEASE_NOTES.md`**: Write the release notes detailing features and bug fixes.
4. **`.github/workflows/ci-windows.yml`**: Update default release tag input if applicable.

### 3.3 NEVER Bump `Casks/utv.rb` Manually Before a Release
>
> [!WARNING]
> **Do NOT manually bump `version` or `sha256` in `Casks/utv.rb` in your release preparation commit.**
>
> **Why?**
> The GitHub Actions workflow (`.github/workflows/build-and-release.yml`) automatically handles Homebrew Cask updates in the `Update Homebrew Cask Formula` step:
>
> 1. It builds and notarizes `UTV-YYYY.X-macOS-arm64.zip`.
> 2. It calculates `sha256sum` of the resulting zip asset.
> 3. It runs `sed -i` to update both `version` and `sha256` in `Casks/utv.rb`.
> 4. It commits with message `chore(release): update homebrew cask for YYYY.X [skip ci]` and pushes to `main`.
>
> If you manually bump `version` in `Casks/utv.rb` prior to release publication:
>
> - The sha256 checksum in the repository will still belong to the previous release.
> - The new zip asset is not yet published on GitHub Releases.
> - Any macOS user running `brew update && brew upgrade --cask utv` against `main` will encounter a download 404 or SHA-256 checksum mismatch error.
>
> Leave `Casks/utv.rb` untouched during release preparation; let CI publish the release and push the updated cask formula.

### 3.4 Kicking Off a Release

To trigger the automated release pipeline via GitHub CLI (`gh`):

```bash
gh workflow run build-and-release.yml -f create_release=true -f version_override=2026.7
```

(If `version_override` is omitted, the workflow auto-detects the latest git tag and increments the minor version.)

Pipeline stages:

1. **Determine Version**: Parses inputs and tags.
2. **Lint codebase**: Executes pre-commit hooks in an Ubuntu environment.
3. **Build macOS**: Compiles on macOS ARM64 with ccache and Homebrew dependencies.
4. **Sign & Notarize macOS**: Applies Developer ID / Ad-Hoc code signing and notarizes via Apple Notary API.
5. **Build Windows**: Compiles on Windows MSVC 2022 with sccache and OpenUTVDeps.
6. **Publish Release**: Creates git tag, publishes GitHub Release with `.github/RELEASE_NOTES.md`, and uploads macOS/Windows zip archives.
7. **Update Homebrew Cask**: Computes macOS archive SHA-256 and commits the updated formula to `main`.
