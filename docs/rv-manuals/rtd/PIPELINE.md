# From Typst to Read the Docs

The manuals are written once, in Typst. Typst makes the PDF and HTML
versions directly. The Read the Docs version takes a longer route: each
chapter is converted to reStructuredText (RST) with Pandoc and then built
with Sphinx. You never edit the RST; it is regenerated on every build.

```text
chapter .typ ──pandoc + manual-lib-pandoc.typ──> RST
             ──sphinx-roles.lua──> Sphinx-ready RST
             ──sphinx-build + manual_ext.py──> Read the Docs HTML
```

`build-rtd.sh` runs every step. To build the site for one product:

```sh
./build-rtd.sh -p openutv
```

The result is in `build/html/index.html`.

## The Steps

1. **Staging.** The script copies the chapters into `build/stage/`, laid out
   like the repository so image paths still work. In place of the real
   `common/manual-lib.typ` it puts `manual-lib-pandoc.typ`, with the
   product and version filled in. The product names come from the real
   library's `products` table, so they are only kept in one place.
2. **Conversion.** Pandoc reads each chapter and writes RST. Pandoc
   understands plain Typst markup but not Typst's layout and scripting
   features, which is why the library has a simpler Pandoc version.
3. **Filtering.** As each chapter is converted, `sphinx-roles.lua` turns the
   things Sphinx treats specially into Sphinx markup: keys, menu paths,
   cross-references and their targets, image sizes, and figures with
   several images side by side.
4. **Building.** The script writes a small Sphinx project (`conf.py` and an
   `index.rst` listing the chapters and appendices of each manual) and runs
   `sphinx-build`. `manual_ext.py` adds what Sphinx lacks: appendix letters,
   numbered side-by-side figures, and figure numbers that restart in every
   chapter.

## Keeping It Working

- Chapters may only use the library's helpers and plain Typst markup. If
  you add a helper to `manual-lib.typ`, add a plain version with the same
  name and arguments to `manual-lib-pandoc.typ`.
- Sphinx runs with warnings treated as errors, so a broken reference or an
  unconverted construct stops the build instead of reaching the site.
- `../build-docs.sh --check` builds every chapter in both pipelines. The
  `docs-check` job in `.github/workflows/pr-checks.yml` runs the same check
  on pull requests that change the manuals.

See `README.md` for setup, the file list, and a suggested
`.readthedocs.yaml`.
