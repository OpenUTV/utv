# Manuals in Typst: Working Notes

Shared notes (human + Claude) for the Typst versions of the manuals. The
user manual and the reference manual are converted and build to PDF, HTML
and Read the Docs (Sphinx) output for all three products (`rv`, `openrv`,
`openutv`) from one source. The remaining Markdown docs will be converted the
same way. This repo is a dev/testing fork, so broken links or docs builds
during the conversion are acceptable.

## Not Yet Done

Details for most of these are under [Open items](#open-items).

- **Publishing.** Nothing publishes the manuals yet: no hosted site, no PDFs
  on releases, nothing bundled in the app. There is no OpenUTV project on
  Read the Docs; the maintainer will set it up (`rtd/README.md` has a
  suggested `.readthedocs.yaml`; the repo's current one is OpenRV's and
  builds the old Markdown site).
- **App Help menu.** `src/plugins/rv-packages/visto_help_menu/openrv_help_menu_mode.mu`
  (lines 350-351) links the user and reference manuals to OpenRV's Read the
  Docs pages. Plan: a per-product build setting (e.g. CMake `RV_DOCS_URL`)
  plus the app version, so each product's app opens its own docs for its
  release; an override for studios hosting docs internally.
- **Release version in released docs.** The release workflow doesn't build
  docs yet; when it does, it should pass its version to `build-docs.sh -v`.
- **Typst PDFs on Read the Docs.** Read the Docs offers a PDF per version,
  normally from Sphinx; serving the Typst PDF instead needs Typst in the Read
  the Docs build. Untried.
- **Remaining conversions:** `rv-gto.md`, `rv-luts.md`, `rv-mu-programming.md`,
  `rv-media-multi-representation.md`. The Help menu links the Mu and GTO
  ones on GitHub.
- **Retiring the Markdown manuals** and the old `docs/` Sphinx site
  (`docs/conf.py`, `docs/index.md`), and repointing the links into them (see
  Decisions).
- **Content fixes** flagged during conversion (see Values to verify, Dated
  content, and the reference manual's "Flagged" list).
- **Code bugs** found while converting (see Code issues).
- **Image originals.** Once the compressed copies in `docs/images-web/` are
  accepted, the originals in `docs/images/` used only by the manuals could
  be dropped.
- **HTML search** across the manuals (see Possible improvements).

## Building

`build-docs.sh` holds all the `typst` command-line details; update it, not
the docs, if the invocation changes. It runs from any directory.

```sh
./build-docs.sh                     # all manuals and products, PDF + HTML, into ./build
./build-docs.sh -m reference        # one manual (user or reference)
./build-docs.sh -p openutv -f pdf   # one product, one format
./build-docs.sh -m user -c 07       # one chapter or appendix (e.g. -c H)
./build-docs.sh -v 2026.8           # version to show (default: docs-version.sh)
./build-docs.sh --check             # build every chapter alone, plus the RTD build
rtd/build-rtd.sh                    # Read the Docs (Sphinx) site, see rtd/README.md
```

The Typst root must be the repository root: the manuals read
`docs/images-web/` and user manual Appendix H reads
`src/plugins/rv-packages/pyside_example/pyside_example.py`. `build/` is
git-ignored.

**Version:** every build shows one (title page, PDF footer, HTML title and
contents, Read the Docs sidebar and front page). `-v` sets it; otherwise
`docs-version.sh` works it out like `CMakeLists.txt` does: the release tag if
the source is at one, else `<latest tag>+dev (<commit>)`, else
`CMakeLists.txt`'s version `+dev`. Chapter text can use `#version`.

**Images:** originals stay in `docs/images/`; the manuals load compressed
copies from `docs/images-web/` (8.3 MB -> 4.6 MB), made by
`compress-images.py` (needs Pillow). After adding or replacing a screenshot
in `docs/images/`, run it again; if it turns a PNG into a JPEG it prints the
new name to use in `img()`.

**CI:** the `docs-check` job in `.github/workflows/pr-checks.yml` runs
`build-docs.sh --check` on pull requests that change `docs/rv-manuals/`,
`docs/images/` or `docs/images-web/`.

## Layout

| File | Purpose |
| --- | --- |
| `build-docs.sh` | Builds the manuals (PDF, HTML, `--check`) |
| `docs-version.sh` | Prints the version the manuals show |
| `compress-images.py` | Makes `docs/images-web/` from `docs/images/` |
| `common/manual-lib.typ` | Product table, `version`, helpers, `manual` template, `title-page` / `body-pages` for master files |
| `common/manual.css` | HTML stylesheet (embedded by the template): contents sidebar, light and dark colors as variables at the top (dark values listed twice: system setting and theme button) |
| `common/manual.js` | HTML behavior (embedded by the template): theme button (automatic / light / dark), current-section highlight, folding chapters, overlay contents on narrow screens, manual name and version atop the contents |
| `rv-user-manual/rv-user-manual.typ` | User manual master: title, contents, includes every chapter |
| `rv-user-manual/rv-user-manual.01.typ` … `.18.typ`, `.A.typ` … `.J.typ` | User manual chapters and appendices (each also builds alone) |
| `rv-reference-manual/rv-reference-manual.typ`, `.01.typ` … `.17.typ` | Reference manual master and chapters |
| `rv-*-manual/deprecated_docs/` | Markdown originals (still published by the old `docs/` Sphinx build via `docs/index.md`) and the retired user manual Appendix H (`rv-user-manual.H.typ`, Crash Reporting) |
| `rtd/` | Read the Docs pipeline: `build-rtd.sh`, Pandoc library twin, Lua filter, Sphinx extension, CSS, pinned requirements; `README.md` and `PIPELINE.md` explain it |

User manual appendix letters differ from the Markdown ones after H was
retired: Markdown I/J/K = Typst H/I/J.

## Conventions

- **Product names:** `#app`, `#appcmd`, `#ioapp`, `#iocmd`, `#lsapp`,
  `#lscmd`, `#pkgcmd`, `#pushapp`, `#pushcmd`, `#org`; `#a-app` / `#A-app`
  for "a UTV" / "an RV". Per-product values live in `products` in
  `manual-lib.typ`.
- **Conditional text:** `#only-for("rv", "openrv")[...]`,
  `#if-feature("name")[...]` (no features defined yet).
- **UI:** `#key("Shift+C")`, `#menu(("File", "Open"))`,
  `#key-table(compact: true, ...)` for long reference tables.
- **Code:** `#appshell(...)` / `#ioshell(...)` / `#lsshell(...)` add a
  `shell>` prompt (lines starting with spaces are continuations);
  `#code-block(lang: none, ...)` has no prompt; `#inline-shell("...")` inline.
- **Images:** always `#img("file.png")`, and `#image-row(...)` for side by
  side (Typst drops `grid` in HTML). All screenshots share one pixel scale,
  using logical pixels (adjusted for DPI, so 144 DPI captures count half):
  PDF = `image-scale` pt per pixel (0.5), HTML = 1 CSS px per pixel. Images
  never enlarge, only shrink to fit, are capped at 90% of the available
  width (`image-max-width`), and are centered. `img(..., width: ...)`
  overrides for one image.
- **Cross-references:** `@label` within a chapter; `#xref(<label>)[Chapter 7]`
  across chapters (shows the fallback text when a chapter is built alone).
  User manual chapter labels are `<ch-…>`, appendix labels `<app-…>`;
  reference manual labels start with `ref-`.
- **Templates:** chapters `#show: manual`, appendices
  `manual.with(appendix: true)`, masters `manual.with(master: true)` plus
  `#title-page[...]` and `#show: body-pages.with[...]`.
- **Read the Docs rule:** chapter files use only library helpers and plain
  Typst markup (no `context`, `target()`, `html.elem`, `measure`, `layout`,
  `state`, `query`). Any new helper in `manual-lib.typ` needs a plain twin in
  `rtd/manual-lib-pandoc.typ`; `--check` catches a missing one.
- **Styling knobs:** PDF table look is the `set table(...)` in the template;
  HTML base text size is 112.5% at the top of `manual.css`; the sidebar width
  and its 700px cutoff are `--toc-width` and the two media queries.

### Typst gotchas

- `;` right after a code expression is swallowed: write `#raw(app)\;`.
- `#app-specific` reads as variable `app-specific`: write `#(app)-specific`.
- `#app.` reads as field access: write `#app\.`.
- A multi-line `#let x = foo()` chain needs parentheses, or the line break
  ends the expression and the rest prints as text.
- In markup, `_ * @ < # $` and lines starting with `-`, `+`, `1.` or `=`
  plus a space are syntax; put such text in backticks or a string.
- In math, multi-letter words are variables: write `"where"`.
- `grid` and `rect` are dropped in HTML export; use `html.elem` wrappers.
- Typst puts the embedded stylesheet and script at the top of `<body>`, so
  scripts must wait for `DOMContentLoaded`.
- `typst query` is deprecated as of Typst 0.15.

## Read the Docs output

`rtd/build-rtd.sh` converts every chapter of both manuals with Pandoc and
builds one Read the Docs-themed Sphinx site with no warnings (`-W`). Keys,
menus, cross-chapter and cross-manual refs, figures, image sizing, rowspan
tables, math, footnotes and term lists all come through. Appendices are
lettered (A, A.1, Table A.1), side-by-side image figures are numbered, and
figure/table numbers restart per chapter (`rtd/manual_ext.py`). The project
name and version come from the product and `docs-version.sh`. Nothing in the
config names a product or site address: each product would be its own Read
the Docs project with `DOCS_PRODUCT` set. See `rtd/README.md` and
`rtd/PIPELINE.md`.

## Open items

### Decisions

- **Big key-binding tables (user manual chapter 4):** currently compact.
  Recommendation: remove them and point readers at Help → Show Current
  Bindings / Describe Key Binding, since the bindings live in `rvui.mu` and
  a copied table will drift. Keep the short "most useful keys" tables.
- **Old Appendix H Markdown:** `deprecated_docs/rv-user-manual-chapter-h.md`
  is still listed in `docs/index.md`; remove both if the old docs should drop
  it too.
- **Retiring the Markdown manuals:** when the Typst output is published,
  replace the `deprecated_docs` entries in `docs/index.md` and repoint the
  links in `docs/rv-manuals/rv-luts.md`, the reference manual's
  `deprecated_docs/rv-reference-manual-chapter-sixteen.md`,
  `docs/rv-packages/rv-nuke-integration.md` and the two GitHub URLs in
  `packages/rv/README.regfiles`.
- **What happens to the Markdown originals** once the Typst version is
  adopted.
- **Where the docs live** (Read the Docs, GitHub Pages, release PDFs,
  bundled in the app): the maintainer's call.

### Values to verify

- RV / OpenRV entries in `products` (`manual-lib.typ`): app names, commands,
  `org`, `prefs` paths are guesses (marked TODO).
- UTV preferences file on Windows (`%APPDATA%\OpenUTV\UTV\OpenUTV\UTV.ini`):
  derived from the QSettings code, not checked on a machine.
- User manual chapter 3: log paths use org `OpenUTV`; the macOS bundle path
  (`/Applications/#app.app/...`) gives `OpenRV.app` for OpenRV, possibly
  wrong.
- User manual chapter 7 inversion matrix: 1s moved from the bottom row to the
  last column (R′ = 1 − R) to match the other matrices; check against a
  trusted source.
- User manual chapter 8 3D LUT memory: changed to "64³ × 3 × 4 bytes" to
  match the stated 3 MB.
- User manual chapter 2: "Refer to the #app README to build and install" is
  wrong for commercial RV; probably needs `#only-for`.

### Code issues found (not fixed)

- `src/plugins/rv-packages/pyside_example/pyside_example.py`: `spinChanged`
  defines `F` twice; the first (using an undefined `p`) is dead code.
  User manual Appendix H shows this file, so fixing it fixes the manual.
- `src/lib/image/IOdpx/IOdpx.cpp:512`: help text lists `source/input_dev`
  twice; the second should be `source/input_serial` (accepted at line 1886).
- `src/bin/apps/rvpush/main.cpp:16`: usage text says `rvpush`; the UTV binary
  is `utvpush`.

### Dated content (user manual)

- Chapter 3: Windows advice (Cygwin, tcsh, command.com).
- Chapter 6: Frame Packed mode (SwitchResX, OS X 10.7, Quadro 4000, old
  `xorg.conf` nVidia options).
- Chapter 12: SpectronIQ displays.
- Chapter 13: Hamachi/vpn.net suggestion.
- Appendix A: CentOS 6/7-era tuning table with "TBD" cells.
- Appendix B: NVIDIA README text (Quadro, TwinView, Xinerama).
- Appendix D: `rv_this.py` now just refers to the Nuke integration package
  docs.
- Appendix E: CentOS 4.6 / Fedora Core 4, ALSA Old/Safe modules (still built
  on Linux).
- Some screenshots were captured large or upscaled; only recapturing fixes
  them (`img(..., width: ...)` can shrink one meanwhile).

### Possible improvements

- Live search for the HTML ("709" → every Rec. 709 mention): client-side JS
  indexing headings/paragraphs/table cells at page load, adding ids to
  headings (Typst only ids labelled ones). About half a day for one manual;
  spanning both manuals needs a shared JSON index (extract from the built
  HTML). Could also feed an in-app help search.
- Max-width text column (~50em) for HTML: shorter lines in wide windows, but
  images wider than the column would shrink to fit it.
- Per-chapter HTML or external image files: the user manual HTML is ~6 MB
  because screenshots are embedded.
- Read the Docs dark mode (the theme has none; would need a Sphinx
  extension).

## Known limitations

- A chapter built alone is numbered "1." (appendices "A") and its
  cross-chapter links show fallback text; only the master build is fully
  correct.
- Typst HTML export is experimental (Typst 0.15.1 used).
- The dark theme's code colors match Typst's 7 highlight colors exactly; if a
  Typst update changes them, code falls back to the light colors.
- Browser zoom enlarges images along with text (expected browser behavior).
- In Safari, the remembered theme choice may not carry between local
  `file://` pages.

## Reference manual (converted 2026-10-07)

Converted from the Markdown (scripted first pass, then hand review of every
chapter). Markdown originals are in `rv-reference-manual/deprecated_docs/`;
`docs/index.md` points there.

Conventions specific to this manual:

- Labels are prefixed `ref-` (chapters `ref-ch-…`) so they can't collide with
  user-manual labels in a combined site.
- Code blocks: Mu, GTO and plain listings are `lang: none` (no highlighter
  exists for Mu); Python, GLSL, bash, XML, JavaScript are tagged.
- `rvpkg`/`rv`/`rvio` command examples use `#shell(pkgcmd, …)` /
  `#appshell` / `#ioshell` so the command follows the product. File
  extensions (`.rvpkg`, `.rv`) and PACKAGE fields (`rv`, `openrv`) stay
  literal.
- API tables with long signatures use proportional column widths (e.g.
  `(2fr, 1fr, 1fr, 2.5fr)`); `auto` columns let one long cell crush the
  description column.

Flagged for the human:

- Ch 16 RVLayoutGroup: description is a copy of RVSourceGroup's (original
  error).
- Ch 13 "Using rvNetwork.py": section was never written ("document here");
  placeholder text now says so.
- Ch 14: QRegExp link points to Qt 4.8 docs.
- Ch 4: PySide2 example updated to PySide6; `createMode()` indentation bug
  fixed.
- `src/plugins/rv-packages/pyside_example`: same dead `F` in `spinChanged`
  (see Code issues).
