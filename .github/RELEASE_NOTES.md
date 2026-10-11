# OpenUTV 2026.13

OpenUTV 2026.13 makes image sequences and still images play back much faster, shrinks the Linux download to about a quarter of its size, adds a hover preview to the timeline, and fixes a crash in `utvio`, sequences with negative frame numbers, and opening files from the Finder.

**To upgrade on macOS:**

```bash
brew update && brew upgrade --cask utv
```

---

### Image sequences and still images play much faster (#109, #113, #96)

Since 2026.9, the default **Auto** caching mode turned caching **off** for EXR, DPX, PNG and other image sequences, when it was meant to turn the look-ahead cache on. Every frame was then decoded one at a time during playback, so the **Reader Threads** setting made no difference.

Auto caching now gives image sequences, and separate still images such as a set of JPEGs or PNGs, the look-ahead cache. On a 6144 × 6144 PNG sequence, playback went from about 2 fps to about 16 fps on the same Mac with 8 reader threads, and Reader Threads works again. Movies are unaffected: H.264 and other inter-frame codecs still get the look-ahead cache, and ProRes and DNxHR still play without caching.

**Auto no longer overrides your choice.** Choosing Look-Ahead, Region or Cache Off from **Tools > Cache Mode** now turns Auto off for that session, so loading more media keeps your choice. The new **Auto (Choose by Media Type)** menu item turns it back on. The log now names the file that decided Auto's choice and why, for example `beachday.jpg is an image or image sequence; using the Look-Ahead cache.` (#113)

For large frames, raise the look-ahead cache size in **Preferences > Caching** so that it holds enough frames: one 6K RGB frame is about 108 MB.

---

### Timeline hover preview (#99)

![Hover preview over the timeline](https://github.com/OpenUTV/utv/raw/main/docs/images/hover-preview.jpg)

Hover the mouse over the timeline to see the frame under the pointer, with its source name, in a panel above the timeline. Choose when it appears under **View > Hover Preview**: Off, When Paused (the default) or Always. The preview uses your display color settings, including OCIO.

The preview needs a cache to draw from. If you see no preview for ProRes, DNxHR or other media that Auto caching plays without a cache, turn on **Look-Ahead** or **Region** caching. Thanks to Seth Rosenthal.

---

### Fixes

- **`utvio` no longer crashes** partway through some renders. The look-ahead cache was starting during batch renders and racing `utvio`'s own frame reads (#106).
- **Sequences with negative frame numbers open.** A sequence such as `frame.-0005.png … frame.0006.png` was listed correctly but failed to open with "No such file or directory". Both spellings of negative frames, `-0005` and `-005`, now work (#108).
- **Sequences whose first frame is missing open**, in the viewer and in the file browser, instead of failing because the first frame of the range isn't on disk (#108).
- **Loading a session no longer starts caching early.** Auto caching waits until the whole session has been read (#104). Thanks to Seth Rosenthal.
- **macOS: opening files from the Finder works with window managers and accessibility tools.** UTV's window was invisible to Accessibility when UTV was launched from the Finder, the Dock or `open`. Files and `rvlink://` links opened from the Finder still arrive (#92). Thanks to Alfonso Casado.
- **Linux: the download is about 70 MB instead of 270 MB.** Static libraries and test programs that nothing uses at run time are no longer packaged; the macOS app also drops about 48 MB of them (#115).
- **Linux: builds no longer pick up Homebrew's Python 3.15.** Homebrew moved its default Python to 3.15 while UTV uses 3.14. On Linux this could link UTV to the wrong Python library and stop it from starting with "No module named 'encodings'" (#107).

### Behind the scenes

- **Out-of-tree C++ Mu modules must be rebuilt for this release.** Mu's `Value` type now uses the compiler's copy constructor instead of an old `memcpy`, which makes it trivially copyable and lets the compiler generate better code, but changes how it's passed between functions (#103). Thanks to Jim Hourihan.
- The RV manuals moved from Markdown to Typst (#100). Thanks to Jim Hourihan.
- A new test media generator, `scripts/testmedia/utv_testmedia.py`, creates test clips, image sequences, layered EXRs and deliberately corrupt files on demand, and can check a UTV build against them (#105).
- The Python OpenColorIO package is now 2.6 or later (#101).
- Windows `build.ps1` works on a fresh machine with Visual Studio 2026 (#93), and the Rocky Linux release build installs its packages again (#94).
- Manual CI builds can now build a given pull request (#110), and the options debug dump labels every field correctly (#111).
- Release notes now list every change and human contributor since the last release (#114), and CI builds reuse their caches again instead of having them evicted (#116).
