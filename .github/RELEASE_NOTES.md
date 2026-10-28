# OpenUTV 2026.15

OpenUTV 2026.15 adds the new Annotation (Beta) tools from OpenRV, sets up OCIO color for HDR presentation and for your footage, fixes flicker in the viewer with HDR PQ presentation on macOS, makes the 10-bit Vulkan view on Linux and Windows usable, and closes several security holes.

**To upgrade on macOS:**

```bash
brew update && brew upgrade --cask utv
```

**Windows:** this release uses OpenUTV Dependencies 26.6, the same as 2026.14. `irm https://openutv.com/install.ps1 | iex` updates UTV; there's no new MSI to install.

---

### Annotation (Beta) (#171)

OpenRV's new annotation tools are in UTV: shapes, text, input smoothing and stamp-based brush rendering, with a new tool panel, per-frame undo and redo, and fixes from the OpenRV team for the cursor, text caret, stylus snapping, fonts and stroke ends. OTIO annotations can carry shapes and text too.

The package is off by default. Turn it on in **Preferences > Packages > Annotation (Beta)**; turning it on turns off the current Annotation package.

---

### OCIO color that sets itself up (#158–#163, #183)

- **The OCIO menu titles show the active color setup**, the display, view and input, so you can see what's applied without opening each menu (#159).
- **UTV picks the OCIO display and view** for the macOS presentation mode and for your footage, and warns when the display you chose doesn't match the presentation (#161, #162).
- **Sources get an OCIO input while an OCIO display is in use**, from the file's metadata or the config's file rules, instead of falling back to the built-in pipeline (#160). With OpenColorIO 2.6, UTV now reads those file rules correctly (#183).
- **Graded video looks unchanged through any OCIO view**: it gets the colorimetric video view, and Rec.2020 HDR video gets the Rec.2020 ACES HDR view (#163).
- **With HDR PQ or HLG presentation, UTV turns on the OCIO display for you**, so a PNG or a Rec.709 clip no longer looks oversaturated until you pick an OCIO setup. Turn OCIO off for a display and UTV leaves it off (#183).
- **Auto-Setup ACES and Apply ACES Setup Now are gone.** They marked every source as ACEScg, whatever it was, and forced the sRGB display, even with HDR presentation. `-autoACES` is still accepted, so scripts keep working, but it does nothing (#158).

---

### macOS: no more flicker with HDR PQ presentation (#182, #186)

With the **macOS Presentation** preference set to HDR PQ (Rec.2100), the viewer flickered in a checkerboard pattern, more often while the mouse moved, even with nothing loaded. UTV was drawing into a surface the window server was still showing. It now waits for one the window server has let go of, on both display paths.

---

### Linux and Windows: the 10-bit Vulkan view (#148, #170)

- The viewer no longer exits at startup with the 10/10/10/2 display format (#148). Thanks to Jim Hourihan.
- UTV picks a 10-bit device and surface format that work, agrees the GL interop image with the driver, and recovers from failed submits and size mismatches. Thanks to Cédrik Fuoco.
- Session Manager hotkeys, cursor shapes and the eyedropper work in the Vulkan view (and the eyedropper in the Metal view on macOS).

---

### Security

- **rvlink URLs and dropped links can't run code.** An rvlink's `-eval`/`-pyeval` is accepted only when it is a single ShotGrid review call with plain data arguments, and `-init` is refused. Dropping text that starts with `http:` no longer goes through a shell (#176).
- **SSL certificate errors fail the request.** Requests packages sent through `networkAccessManager()` accepted invalid certificates. Set `UTV_IGNORE_SSL_ERRORS=1` for sites whose certificates your system doesn't trust (#185).
- Installing a package with an image-format plugin no longer runs `makeFBIOformats` through a shell, and rvNuke reads its preferences as data instead of running them (#175).
- The macOS update prompt writes its upgrade script to a private temporary file instead of a fixed path in `/tmp` (#177).
- Builds made with the Apple ProRes SDK reallocate the decode frame when the frame size changes (#184). The published builds don't include the SDK.

---

### Fixes

- **Windows: high-DPI scaling is on by default**, so the UI is no longer tiny on scaled displays. Set `RV_NO_QT_HDPI_SUPPORT=1` to turn it off, on any platform (#144). Thanks to Jim Hourihan.
- **Windows: when the viewer crashes, UTV says so** with the error code and the `openutv-diagnostics.cmd` to run for a bug report, instead of disappearing without a message (#189).
- **Windows: paths with emoji and other characters outside the Basic Multilingual Plane open** instead of failing (#178).
- **Export > Snapshot** wrote a blank white image on macOS and with the 10-bit Vulkan view. It now saves the frame (#147). Thanks to Jim Hourihan.
- **UTV quits** when the Console, Preferences or another tool window is still open (#170). Thanks to Cédrik Fuoco.
- **Leaving presentation mode** no longer frees the output's framebuffers in the wrong context, and Windows reads the display's color profile safely (#170). Thanks to Cédrik Fuoco.
- **Playback**: EXR with WAV audio no longer stutters, the number of open FFmpeg decoders is capped so memory stops growing during long playback, and a track's hardware decoder is reused when its decoder reopens instead of leaking a device each time (#164, #167). Thanks to Bernard Laberge.
- **Paint and annotations** no longer show stale strokes from the paint cache (#165). Thanks to Roger Nelson and Cédrik Fuoco.
- **utvio** no longer crashes at exit on Linux with NVIDIA and Mesa drivers, or on Rocky Linux 9 with `BadAccess` (#145, #174). Thanks to Jim Hourihan, Éloïse Brosseau and Bernard Laberge.
- **macOS**: unzipping a release with `unzip` no longer leaves `._*` files that UTV tried to load (#172), and Python's bytecode cache is written to `~/Library/Caches/UTV` instead of inside UTV.app, which broke its code signature (#173).
- `-debug profile` no longer crashes with the Metal and Vulkan views (#168). The session manager reorders inputs faster with previews, and rvlink remembers the RV you chose last time (#164). Thanks to Éloïse Brosseau and deltag0.

### Behind the scenes

- Windows `build.ps1` installs a working Build Tools compiler and the Vulkan SDK (#143). Thanks to Jim Hourihan.
- A weekly workflow watches OpenRV for new commits to port (#169).
- PR Checks run only for open PRs and for edits that change what they check (#181), and the Linux test step fails when headless utvio fails (#187).

### Contributors

Thanks to everyone who worked on this release:

- Jim Hourihan (@jimhourihan)
- Cédrik Fuoco (@cedrik-fuoco-adsk)
- Éloïse Brosseau (@eloisebrosseau)
- Roger Nelson (@rogernelson)
- Bernard Laberge (@bernie-laberge)
- Mike Kucera (@mikekucera)
- deltag0 (@deltag0)

The annotation, playback, paint-cache and Rocky Linux fixes were written for OpenRV and ported to UTV.
