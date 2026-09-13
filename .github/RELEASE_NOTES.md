# OpenUTV 2026.3

### macOS Launcher & Dependency Self-Healing

- **Native Terminal Script Execution (`.command`)**: Replaced AppleScript-based terminal launching in `UTVLauncher.mm` with a native temporary `.command` executable opened via macOS `NSWorkspace`. Bypasses macOS TCC / Automation permissions entirely, ensuring terminal windows immediately execute the installation sequence without silent drops or permission errors.
- **Clipboard Command Auto-Copy**: Automatically copies the exact `brew install ... && brew link --overwrite ffmpeg-full` command directly to the macOS pasteboard (`NSPasteboard`) so it is immediately available if preferred.
- **Dynamic Remote Dependency Manifest**: Integrated dynamic dependency resolution querying `https://raw.githubusercontent.com/OpenUTV/utv/main/deploy/dependencies.json` with a 1.5-second timeout and offline fallback. Allows instant formula adjustments, naming updates, and workarounds on GitHub without recompiling the application.
- **Dependency Conflict Healing**: Automatically runs `brew link --overwrite ffmpeg-full` during dependency setup to resolve linking conflicts when standard `ffmpeg` is pre-installed.
- **Deduplicated Dependency Checks**: Deduplicated detected missing packages while preserving optimal installation order.

### Diagnostics & Issue Reporting

- **Automated Diagnostic Packager (`openutv-diagnostics`)**: Added an automated diagnostic tool that bundles system hardware specifications (CPU, RAM, GPU Metal device), macOS version, Homebrew environment and formula versions (`qt`, `boost`, `ffmpeg-full`, `openjpeg`, `openimageio`, `openexr`, `pyside`), OpenUTV logs (`~/Library/Logs/OpenUTV/UTV.log`), recent crash reports (`~/Library/Logs/DiagnosticReports/UTV*.ips`), and user preferences into a timestamped zip archive in `~/Downloads`.
- **Integrated GitHub Issue Reporting**: Added **Help -> Report Issue on GitHub...** and a launcher fallback button that generates the diagnostic archive, reveals it in Finder, and opens the pre-filled GitHub Bug Report template ready for attachment.
- **Manual Diagnostics Export**: Added **Help -> Collect Diagnostics Package...** to export debug bundles at any time.

### Version Upgrade Checker

- **GitHub Release Checker (`openutv-check-updates`)**: Added an update checker that queries the GitHub Releases API for new OpenUTV releases.
- **1-Click Homebrew Cask Upgrade**: If OpenUTV was installed via Homebrew Cask, the update prompt offers a 1-click option to launch Terminal and run `brew upgrade --cask utv`.
- **In-App Menu**: Added **Help -> Check for Updates...** to check for newer releases at any time.

### Intelligent Caching & Video Playback

- **Intra-Frame Video Auto-Bypass**: Formats like Apple ProRes and Avid DNxHR/DNxHD route to **No Caching** (`NeverCache`) by default for instant real-time playback without RAM saturation.
- **Inter-Frame Video & Image Sequences**: Automatically engages **Look-Ahead Cache** (`BufferCache`) for smooth frame-accurate playback.
- **Zero-Wait Buffer Overrun**: Default Look-Ahead wait time is set to `0.0s`, allowing on-the-fly decoding without stalling.
- **Dynamic Hardware RAM Ceiling**: Automatically clamps cache size to safe limits (85% physical RAM).

### Code Signing & Apple Notarization

- **Apple Notarization & Stapled Tickets**: Fully signed with Developer ID Application certificate and notarized by Apple with stapled tickets.
- **Hardened Runtime**: Built and codesigned with macOS Hardened Runtime and valid entitlements.

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

Download `UTV-2026.3-macOS-arm64.zip` below, extract `UTV.app`, and move it to `/Applications`.
