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

### 1.3 Multi-OS Architecture & Cross-Platform Integrity

OpenUTV is a cross-platform desktop application targeting **macOS (Apple Silicon & Intel)**, **Windows (x64 MSVC)**, and **Linux (Ubuntu/glibc)**.

- **Universal Core Fixes**:
  - When fixing bugs or adding features (e.g. media loading, session serialization, OpenGL pipeline, shader compilation, UI event dispatch, menu synchronization), changes must resolve the root cause cleanly across all operating systems.
  - Never apply superficial OS-specific band-aids to core shared modules (`src/lib/ip`, `src/lib/app`, `src/lib/image`, etc.) when the defect is architectural.
- **Strict Isolation of Platform-Specific Behavior**:
  - If platform-specific functionality is strictly required (e.g. Apple event loops, Windows registry probing, POSIX signal handling, X11/Wayland display handling), it **MUST** be explicitly isolated behind platform preprocessor guards:
    - C++ preprocessor: `#ifdef PLATFORM_DARWIN`, `#ifdef PLATFORM_WINDOWS`, `#ifdef PLATFORM_LINUX`, or Qt macros `#if defined(Q_OS_MACOS)`, `#if defined(Q_OS_WIN)`, `#if defined(Q_OS_LINUX)`.
    - CMake build logic: `IF(APPLE)`, `IF(RV_TARGET_WINDOWS)`, `IF(RV_TARGET_LINUX)`.
    - Build scripts: separate shell/PowerShell blocks or platform conditionals.
  - Never introduce non-standard or platform-bound types (e.g. POSIX `ssize_t`) in shared headers without explicit fallback typedefs for MSVC/Windows (`#if defined(_MSC_VER) ...`).
- **Matrix Validation**:
  - All Pull Requests must build cleanly across the GitHub Actions CI matrix (`macOS`, `Windows`, `Linux`).

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

### 2.7 Homebrew Dynamic Link Sanitization & Symlink Normalization

- **Mach-O `LC_ID_DYLIB` Behavior**:
  - macOS linkers (`ld64`/`dyld`) do not record the filename given on the command line; they copy the library's embedded install name (`LC_ID_DYLIB`).
  - Homebrew formulas like OpenJPH (`openjph`) set their `LC_ID_DYLIB` to a versioned path (e.g. `/opt/homebrew/opt/openjph/lib/libopenjph.0.31.dylib`).
  - Whenever Homebrew upgrades the package (e.g. from 0.31 to 0.32), the older dylib file is deleted from the user's system, causing plugins like `mio_ffmpeg.dylib` and `io_htj2k.dylib` to fail loading at runtime (`Library not loaded: libopenjph.0.31.dylib (no such file)`).
- **Automated Normalization (`sanitize_homebrew_links.py`)**:
  - `src/build/sanitize_homebrew_links.py` is invoked during `build.sh` and before codesigning in `build-and-release.yml`.
  - It uses `install_name_tool -change` to rewrite Cellar paths to `/opt/homebrew/opt/...`.
  - For OpenJPH, it automatically maps any versioned link (`libopenjph.*.dylib`) to the unversioned symlink `/opt/homebrew/opt/openjph/lib/libopenjph.dylib`. Because Homebrew always maintains this symlink to the currently installed version, OpenUTV remains compatible across Homebrew updates without crashing.

---

## 3. CI/CD Architecture & Release Workflow

### 3.1 Conventional Commits & Branch Strategy

All contributions to OpenUTV must follow the **Conventional Commits** specification:

```text
<type>(<optional scope>): <description>

[optional body]

[optional footer(s)]
```

- **Supported Types**: `feat`, `fix`, `perf`, `docs`, `build`, `ci`, `test`, `chore`, `style`, `refactor`.
- **Enforcement**:
  - All Pull Requests must use conventional PR titles and commit messages.
  - Automated PR checking is enforced via `.github/workflows/pr-checks.yml` using `commitlint` with configuration in [`.commitlintrc.js`](.commitlintrc.js).
  - Merges to `main` must occur via Pull Requests to ensure clean semantic history and commitlint validation.

### 3.2 Automated Workflows Overview

The CI/CD pipeline consists of 7 modular workflows:

1. **`pr-checks.yml`** (Pull Requests):
   - Validates PR title and every commit message against Conventional Commits.
   - Executes pre-commit hooks (Python/Ruff, clang-format, cmake-format, markdownlint).
   - Validates build script syntax when code changes occur.
2. **`dev-build.yml`** (Merges to `main`):
   - Triggered on code path changes to `main` (`src/`, `cmake/`, `build.sh`, etc.).
   - Compiles and packages macOS, Windows, and Linux.
   - Applies full Apple Developer ID codesigning and Apple Notary Service notarization.
   - Updates the rolling `dev-build` pre-release tag in-place without generating email notifications to repository watchers.
   - Automatically generates a categorized changelog of commits since the last stable release.
3. **`branch-build.yml`** (Feature Branches):
   - Triggers on pushes to any branch in `OpenUTV/utv` (excluding forks).
   - Builds ad-hoc test binaries for macOS, Windows, and Linux and uploads them as Actions artifacts for QA testing before opening a PR.
4. **`release.yml`** (Production Release):
   - Triggered via `workflow_dispatch`.
   - Execution order: **Lint -> Determine Version -> Build (macOS/Win/Linux) -> Sign & Notarize -> Publish Release**.
   - Generates release checksums (`checksums.sha256`).
   - Automatically generates release notes categorized by Conventional Commit types (`scripts/generate-changelog.sh`).
5. **`publish-packages.yml`** (Triggered on Release Publication):
   - Automatically pushes cask updates to `OpenUTV/homebrew-utv`.
   - Updates the Scoop manifest in `OpenUTV/scoop-utv`.
   - Submits update PR to `microsoft/winget-pkgs` via `wingetcreate`.
   - Packs and pushes Chocolatey `.nupkg` to `community.chocolatey.org`.
6. **`codeql.yml`**:
   - Weekly scheduled CodeQL security scanning for C++ and Python vulnerabilities.
7. **`dependabot-auto-merge.yml`**:
   - Automatically reviews and merges patch-level dependency updates.

### 3.3 Triggering a Production Release

To trigger a release build using the GitHub CLI:

```bash
gh workflow run release.yml -f create_release=true -f version_override=2026.8
```

Options for `release.yml`:

- `version_override`: Optional custom version (e.g. `2026.8`). If left empty, CI automatically increments the minor version based on the latest git tag.
- `create_release`: Set to `true` to publish the GitHub release and trigger `publish-packages.yml`. Set to `false` for a dry-run test build.
- `platforms`: Choice of `all`, `macos-only`, `windows-only`, or `linux-only`.

### 3.4 Package Manager Secrets & Configuration

The package publishing pipeline requires the following per-service repository secrets:

| Secret | Purpose | Permissions / Scope |
| :--- | :--- | :--- |
| `HOMEBREW_TAP_TOKEN` | Updates `OpenUTV/homebrew-utv` | GitHub PAT with `repo` scope |
| `SCOOP_BUCKET_TOKEN` | Updates `OpenUTV/scoop-utv` | GitHub PAT with `repo` scope |
| `WINGET_PAT` | Submits PR to `microsoft/winget-pkgs` | GitHub PAT with `public_repo` scope |
| `CHOCO_API_KEY` | Pushes to Chocolatey Community Repository | API key from `community.chocolatey.org` |
| `GH_TOKEN_DEPS_READ` | Accesses private vendor SDKs | GitHub PAT with `repo:read` scope |
| `MACOS_CERTIFICATE` | Developer ID Application certificate (Base64) | Apple Developer Program |
| `MACOS_CERTIFICATE_PWD` | Password for macOS certificate `.p12` | - |
| `APPLE_API_KEY` | App Store Connect API Key (Base64) | Apple Notary Service API |
| `APPLE_API_KEY_ID` | App Store Connect Key ID | Apple Notary Service API |
| `APPLE_API_ISSUER` | App Store Connect Issuer UUID | Apple Notary Service API |

### 3.5 One-Time Windows Package Manager Registration Scripts

To bootstrap package manager registrations, execute the provided setup scripts on a Windows machine:

1. **Scoop**:

   ```powershell
   pwsh .\scripts\register-scoop.ps1 -Version "2026.7"
   ```

2. **winget**:

   ```powershell
   pwsh .\scripts\register-winget.ps1 -Version "2026.7" -Submit
   ```

3. **Chocolatey**:

   ```powershell
   pwsh .\scripts\register-chocolatey.ps1 -Version "2026.7" -ApiKey "<YOUR_API_KEY>"
   ```
