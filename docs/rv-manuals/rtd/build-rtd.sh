#!/usr/bin/env bash
#
# Convert the Typst manuals to RST with Pandoc and build them as one Sphinx
# site (Read the Docs theme). Proof of concept for the Read the Docs phase.
#
#   ./build-rtd.sh                    openutv, all manuals, into ./build
#   ./build-rtd.sh -p rv -o /tmp/rtd  another product / output dir
#   ./build-rtd.sh --rst-only         stop after writing the RST
#   ./build-rtd.sh --version 2026.8   version shown in the docs (default:
#                                     ../docs-version.sh)
#
# Needs pandoc (3.x) and, unless --rst-only, Sphinx 7+ with
# sphinx_rtd_theme (see README for a private install; don't use a bare
# `pip`, which may be an old Python's).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANUALS_DIR="$(cd "$HERE/.." && pwd)"          # docs/rv-manuals
REPO="$(cd "$MANUALS_DIR/../.." && pwd)"

# directory / file prefix, and title, of each manual in site order
MANUALS=(rv-user-manual rv-reference-manual)
manual_title() {
    case "$1" in
        rv-user-manual)      echo "User Manual" ;;
        rv-reference-manual) echo "Reference Manual" ;;
    esac
}

PRODUCT=openutv
OUTDIR="$HERE/build"
RST_ONLY=0
VERSION=""

usage() {
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--product) PRODUCT="$2"; shift 2 ;;
        -o|--outdir)  OUTDIR="$2"; shift 2 ;;
        --rst-only)   RST_ONLY=1; shift ;;
        --version)    VERSION="$2"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

case "$PRODUCT" in rv|openrv|openutv) ;; *) echo "unknown product: $PRODUCT" >&2; exit 2 ;; esac
command -v pandoc >/dev/null || { echo "pandoc not found (brew install pandoc)" >&2; exit 1; }
[[ -n "$VERSION" ]] || VERSION="$("$MANUALS_DIR/docs-version.sh")"
# the product's display name (UTV, OpenRV, RV) from the products table
APP="$(awk -v p="    $PRODUCT: (" 'index($0, p) == 1 { f = 1 } f && /app: "/ { sub(/.*app: "/, ""); sub(/".*/, ""); print; exit }' \
    "$MANUALS_DIR/common/manual-lib.typ")"
[[ -n "$APP" ]] || { echo "no app name for $PRODUCT in manual-lib.typ" >&2; exit 1; }

# Staging tree mirrors the repo layout so the chapters' relative paths
# (../common/, ../../images-web/, ../../../src/...) resolve; docs/images-web
# and src are symlinks.
STAGE="$OUTDIR/stage"
DOCS="$STAGE/docs"
rm -rf "$STAGE"
mkdir -p "$DOCS/rv-manuals/common"
ln -s "$REPO/docs/images-web" "$DOCS/images-web"
ln -s "$REPO/src" "$STAGE/src"

# Pandoc library = products table from the real manual-lib.typ + Pandoc
# helpers, with the product filled in. Chapters import ../common/manual-lib.typ.
{
    sed -n '/^#let products = (/,/^#let product = sys.inputs/p' "$MANUALS_DIR/common/manual-lib.typ" | sed '$d'
    sed -e "s/PRODUCT_PLACEHOLDER/$PRODUCT/" -e "s|VERSION_PLACEHOLDER|$VERSION|" "$HERE/manual-lib-pandoc.typ"
} > "$DOCS/rv-manuals/common/manual-lib.typ"

# Convert each chapter. Run from the chapter directory so image paths in the
# filter resolve. Collect toctree entries per manual as we go.
failures=0
toctrees=""
shopt -s nullglob
for m in "${MANUALS[@]}"; do
    srcdir="$MANUALS_DIR/$m"
    files=("$srcdir/$m".[0-9][0-9].typ "$srcdir/$m".[A-Z].typ)
    [[ ${#files[@]} -gt 0 ]] || continue
    out="$DOCS/rv-manuals/$m"
    mkdir -p "$out"
    cp "${files[@]}" "$out/"
    chapters=()
    appendices=()
    pushd "$out" >/dev/null
    for src in "$m".[0-9][0-9].typ "$m".[A-Z].typ; do
        rst="${src%.typ}.rst"
        if ! pandoc -f typst -t rst --wrap=none --lua-filter="$HERE/sphinx-roles.lua" "$src" -o "$rst"; then
            echo "FAIL  $m/$src" >&2
            failures=$((failures + 1))
            continue
        fi
        if [[ "$src" =~ \.[0-9][0-9]\.typ$ ]]; then
            chapters+=("rv-manuals/$m/${rst%.rst}")
        else
            appendices+=("rv-manuals/$m/${rst%.rst}")
        fi
    done
    rm -f ./*.typ
    popd >/dev/null
    echo "$m: converted $(( ${#chapters[@]} + ${#appendices[@]} )) files"

    title="$(manual_title "$m")"
    toctrees+=$'\n'".. toctree::"$'\n'"   :numbered:"$'\n'"   :maxdepth: 2"$'\n'"   :caption: $title"$'\n\n'
    toctrees+="$(printf '   %s\n' "${chapters[@]}")"$'\n'
    if [[ ${#appendices[@]} -gt 0 ]]; then
        toctrees+=$'\n'".. toctree::"$'\n'"   :numbered:"$'\n'"   :maxdepth: 2"$'\n'"   :caption: $title Appendices"$'\n\n'
        toctrees+="$(printf '   %s\n' "${appendices[@]}")"$'\n'
    fi
done
[[ $failures -eq 0 ]] || { echo "$failures conversion(s) failed" >&2; exit 1; }
echo "RST in $DOCS/rv-manuals"

[[ $RST_ONLY -eq 1 ]] && exit 0

# Minimal Sphinx project: each manual's chapters, and its appendices, in their
# own numbered toctree; manual_ext.py turns appendix numbers into letters.
mkdir -p "$DOCS/_static" "$DOCS/_templates"
cp "$HERE/custom.css" "$DOCS/_static/"
# version under the project name in the sidebar (the theme leaves that to
# Read the Docs' version menu, which only exists on the hosted site)
cat > "$DOCS/_templates/layout.html" <<'EOF'
{% extends "!layout.html" %}
{% block sidebartitle %}{{ super() }}<div class="version">Version {{ release }}</div>{% endblock %}
EOF
cp "$HERE/manual_ext.py" "$DOCS/"
cat > "$DOCS/conf.py" <<EOF
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
extensions = ["manual_ext"]
project = "$APP Manuals"
version = release = "$VERSION"
templates_path = ["_templates"]
# name the top page explicitly: Sphinx < 2.0 defaults to "contents"
root_doc = master_doc = "index"
html_theme = "sphinx_rtd_theme"
html_static_path = ["_static"]
html_css_files = ["custom.css"]
numfig = True
EOF
{
    title="$APP Manuals"
    echo "$title"
    echo "${title//?/=}"
    echo
    echo "Version $VERSION"
    printf '%s\n' "$toctrees"
} > "$DOCS/index.rst"

command -v sphinx-build >/dev/null || {
    echo "sphinx-build not found; RST is in $DOCS/rv-manuals" >&2
    echo "Make a private one:  python3 -m venv $HERE/build/venv && $HERE/build/venv/bin/pip install -r $HERE/requirements.txt" >&2
    echo "then run:            PATH=\"$HERE/build/venv/bin:\$PATH\" $0" >&2
    exit 1
}
sphinx_major="$(sphinx-build --version 2>&1 | sed -n 's/.* \([0-9][0-9]*\)\..*/\1/p')"
if [[ -z "$sphinx_major" || "$sphinx_major" -lt 7 ]]; then
    echo "$(command -v sphinx-build) is $(sphinx-build --version 2>&1); need Sphinx 7 or newer." >&2
    echo "Make a private one:  python3 -m venv $HERE/build/venv && $HERE/build/venv/bin/pip install -r $HERE/requirements.txt" >&2
    echo "then run:            PATH=\"$HERE/build/venv/bin:\$PATH\" $0" >&2
    exit 1
fi
# -W: treat warnings as errors so drift between the two libraries shows up
sphinx-build -q -W -b html "$DOCS" "$OUTDIR/html"
echo "HTML in $OUTDIR/html/index.html"
