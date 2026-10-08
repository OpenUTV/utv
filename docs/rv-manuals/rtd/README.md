# Read the Docs output from the Typst manuals (proof of concept)

Converts the Typst manuals to RST with Pandoc and builds them with Sphinx
and the Read the Docs theme. The Typst files stay the source of truth.
`PIPELINE.md` walks through the steps.

```sh
./build-rtd.sh                  # openutv → build/html/index.html
./build-rtd.sh -p rv            # another product
./build-rtd.sh --rst-only       # just the RST (build/stage/...)
./build-rtd.sh --version 2026.8 # version to show (default: ../docs-version.sh)
```

Needs `pandoc` 3.x, plus Sphinx 7+ and `sphinx-rtd-theme` for the HTML.
`requirements.txt` pins the tested versions (Python 3.11+). Install them in a
private environment (a bare `pip` may belong to an old system Python):

```sh
python3 -m venv build/venv && build/venv/bin/pip install -r requirements.txt
PATH="$PWD/build/venv/bin:$PATH" ./build-rtd.sh
```

The Sphinx build runs with `-W`, so any warning fails it.
`../build-docs.sh --check` runs this build too when `pandoc` and
`sphinx-build` are on the `PATH`, and the `docs-check` job in
`.github/workflows/pr-checks.yml` runs it on pull requests that change
`docs/rv-manuals/`, `docs/images/` or `docs/images-web/`.

## How it works

| File | Role |
| --- | --- |
| `manual-lib-pandoc.typ` | Pandoc version of the helpers in `manual-lib.typ`: same API, plain implementations. The script prepends the `products` table from the real `manual-lib.typ`, so product data lives in one place. |
| `sphinx-roles.lua` | Pandoc filter: keys → `:kbd:`, menus → `:menuselection:`, `@label`/`xref` → `:ref:`, label targets, image sizing (pixels × 72 / DPI, same as the Typst HTML), multi-image figures → `multi-figure`, curly-quote fix. |
| `manual_ext.py` | Sphinx extension: the `multi-figure` directive (numbered figure with images side by side), appendix letters (A, A.1, Table A.1), and figure/table numbers restarted in every chapter so the two manuals don't share counters. |
| `custom.css` | Lets long table cells wrap in the Read the Docs theme; lays out `multi-figure` images in a row. |
| `requirements.txt` | Pinned Sphinx and theme versions. |
| `build-rtd.sh` | Stages the chapters with the Pandoc library, converts each chapter, writes `conf.py`/`index.rst`, runs Sphinx. |

## Rules for chapter files

Pandoc's Typst reader doesn't support `context`, `target()`, `html.elem`,
`measure`, `layout`, `state`, `query` or `sys.inputs`. Chapter files must use
only the library helpers and plain Typst markup; anything Typst-specific
stays in `manual-lib.typ`, with a plain equivalent added to
`manual-lib-pandoc.typ`.

## Hosting on Read the Docs

Not set up yet. The repo's `.readthedocs.yaml` is OpenRV's, which builds the
old Markdown site from `docs/conf.py`. To publish these manuals instead,
something like this should work (untested on Read the Docs itself):

```yaml
version: 2
build:
  os: ubuntu-24.04
  tools:
    python: "3.13"
  jobs:
    pre_install:
      - mkdir -p $HOME/bin
      - >-
        curl -fsSL https://github.com/jgm/pandoc/releases/download/3.12/pandoc-3.12-linux-amd64.tar.gz
        | tar -xz --strip-components=2 -C $HOME/bin pandoc-3.12/bin/pandoc
    build:
      html:
        - PATH=$HOME/bin:$PATH docs/rv-manuals/rtd/build-rtd.sh -p "${DOCS_PRODUCT:-openutv}" -o $READTHEDOCS_OUTPUT
python:
  install:
    - requirements: docs/rv-manuals/rtd/requirements.txt
```

Nothing in it names a product or a site address, so the same file serves
every product: each product is its own Read the Docs project, with
`DOCS_PRODUCT` (`rv`, `openrv` or `openutv`) set under the project's
environment variables. The version shown comes from `../docs-version.sh`,
which uses the tag when Read the Docs builds one (`2026.8`) and
`<tag>+dev (<commit>)` otherwise.

Ubuntu's own `pandoc` package is too old for the Typst reader, hence the
download. The PDF comes from Typst (`../build-docs.sh`), not from Sphinx, so
leave out `formats: [pdf]`.
