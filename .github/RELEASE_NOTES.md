# OpenUTV 2026.14

OpenUTV 2026.14 moves macOS and Linux to Python 3.15, fixes UTV's Python plugins with today's Homebrew, adds NVIDIA hardware decoding and faster software H.264/HEVC decoding on Windows, fixes high-DPI and mixed-scale multi-monitor display, and gets the Linux build starting on a normal desktop.

**To upgrade on macOS:**

```bash
brew update && brew upgrade --cask utv
```

**Windows: this release needs OpenUTV Dependencies 26.6.** `irm https://openutv.com/install.ps1 | iex` installs it automatically. If you use the zip, install `OpenUTVDeps-26.6-win64.msi` first. Installing 26.6 removes 26.5, so 2026.13 and older will no longer start.

---

### Python 3.15 on macOS and Linux (#128, #129, #131)

Homebrew's PySide6 moved to Python 3.15, which left 2026.13's Python plugins unable to load, with errors such as `python module media_info could not be imported`. UTV now uses Python 3.15 on macOS and Linux, and the Homebrew cask installs the Python version UTV was built with.

UTV can also load Homebrew's PySide6 when it's built for a different Python version, so the next time Homebrew moves PySide ahead of UTV, the Python plugins keep working. Windows stays on Python 3.14 from OpenUTV Dependencies.

If you have your own Python packages for UTV, install them for Python 3.15.

---

### `import OpenImageIO` works in UTV's Python (#136, #137)

- **macOS and Linux:** UTV now ships the OpenImageIO Python module, from OpenImageIO's own Python 3.15 packages. Homebrew only builds it for Python 3.14.
- **Windows:** the OpenImageIO module from OpenUTV Dependencies failed with `DLL load failed`. UTV now lets it find its DLLs.

UTV still reads images with OpenImageIO directly; this is only for your own Python scripts.

---

### Windows: faster video decoding (#121, #125, #96)

- **NVIDIA GPUs can decode with NVDEC.** OpenUTV Dependencies 26.6 adds NVIDIA, AMD and Intel hardware decoders to FFmpeg. UTV now tries NVIDIA's first, and other GPUs keep using D3D11VA.
- **Software H.264 and HEVC decoding uses all your cores.** UTV only split decoding within a frame, and most camera files have one slice per frame, so they decoded on one core. They now decode several frames at once. ProRes, DNxHR and hardware decoding are unchanged.
- When a codec that can be hardware-decoded is decoded on the CPU, the log now says why, once per codec.

---

### Fixes

- **High-DPI displays draw correctly** (#124). With fractional scaling on Linux the image was drawn too large and off-center, and on a 2x presentation display such as Sidecar it filled only a quarter of the output. Pointer coordinates now match the image too. Thanks to Jim Hourihan.
- **Presentation mode opens on the right monitor** with monitors at different scales on Windows and on Linux Wayland (#138, #135). UTV now asks Qt which screen a window is on instead of working it out from window positions. On the COSMIC desktop the window can still open on the wrong screen, because of a COSMIC bug (#139). Thanks to Jim Hourihan.
- **Linux: UTV starts on a normal desktop.** It no longer needs the `-dev` packages of the GPU driver libraries (#118). It also finds Qt's Wayland and X11 plugins, and `build.sh --install-deps` installs `flex` and `bison` for Homebrew builds (#123). Thanks to Jim Hourihan.
- **macOS: Upgrade from the update prompt installs the new version.** It ran `brew upgrade` without `brew update`, so right after a release Homebrew didn't know about it yet and the prompt still said the upgrade had finished (#117).

### Behind the scenes

- **Windows installs only through `install.ps1` or the zip.** The winget, Scoop and Chocolatey packages, which had stopped being published, were removed (#122).
- The Rocky Linux release build was dropped; Linux releases are built on Ubuntu. The README explains installing on Linux (#119).
- Windows CI retries Chocolatey installs (#126). The dev build keeps its release when moving the tag fails (#132).
- FITS images round-trip on Linux now. Windows still reads them back at the wrong size (#67, #140).

### Contributors

Thanks to everyone who worked on this release:

- Jim Hourihan (@jimhourihan)
- Michael Oliver (@mcoliver)
