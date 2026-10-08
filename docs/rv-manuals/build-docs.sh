#!/usr/bin/env bash
#
# Build the Typst manuals to PDF and/or HTML.
#
# All typst invocation details (root, features, inputs) live here, so if the
# command line changes only this script needs updating.
#
#   ./build-docs.sh                        all manuals, all products, PDF + HTML
#   ./build-docs.sh -m user -p openutv     one manual, one product
#   ./build-docs.sh -m reference -c 07     just chapter 7 of the reference manual
#   ./build-docs.sh --check                build every chapter alone, report errors
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repository root: Typst may only read files below --root, and the manuals read
# docs/images-web/ and src/plugins/ (user manual Appendix H).
ROOT="$(cd "$HERE/../.." && pwd)"

# manual name -> directory / file prefix (a function, not an associative
# array: macOS ships bash 3.2)
manual_dir() {
    case "$1" in
        user)      echo rv-user-manual ;;
        reference) echo rv-reference-manual ;;
        *)         return 1 ;;
    esac
}
ALL_MANUALS=(user reference)
ALL_PRODUCTS=(openutv openrv rv)

MANUALS=()
PRODUCTS=()
FORMAT=all
OUTDIR="$HERE/build"
CHAPTER=""
CHECK=0
VERSION=""

usage() {
    cat <<EOF
usage: $(basename "$0") [options]

  -m, --manual NAME    user or reference (repeatable or comma separated;
                       default: all)
  -p, --product NAME   rv, openrv or openutv (repeatable or comma separated;
                       default: all)
  -f, --format FMT     pdf, html or all (default: all)
  -o, --outdir DIR     output directory (default: $HERE/build)
  -v, --version VER    version shown in the manuals (default: worked out
                       by docs-version.sh from git tags or CMakeLists.txt)
  -c, --chapter ID     build one chapter/appendix file of a single manual
                       instead of the whole manual, e.g. 07 or H
      --check          build every chapter and appendix on its own, in both
                       formats, and report any that fail (no output kept)
  -h, --help           show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--manual)   IFS=, read -r -a m <<< "$2"; MANUALS+=("${m[@]}"); shift 2 ;;
        -p|--product)  IFS=, read -r -a p <<< "$2"; PRODUCTS+=("${p[@]}"); shift 2 ;;
        -f|--format)   FORMAT="$2"; shift 2 ;;
        -o|--outdir)   OUTDIR="$2"; shift 2 ;;
        -v|--version)  VERSION="$2"; shift 2 ;;
        -c|--chapter)  CHAPTER="$2"; shift 2 ;;
        --check)       CHECK=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ ${#MANUALS[@]} -eq 0 ]] && MANUALS=("${ALL_MANUALS[@]}")
[[ ${#PRODUCTS[@]} -eq 0 ]] && PRODUCTS=("${ALL_PRODUCTS[@]}")

for m in "${MANUALS[@]}"; do
    manual_dir "$m" >/dev/null || { echo "unknown manual: $m" >&2; exit 2; }
done
for p in "${PRODUCTS[@]}"; do
    case "$p" in rv|openrv|openutv) ;; *) echo "unknown product: $p" >&2; exit 2 ;; esac
done
case "$FORMAT" in
    pdf)  FORMATS=(pdf) ;;
    html) FORMATS=(html) ;;
    all)  FORMATS=(pdf html) ;;
    *)    echo "unknown format: $FORMAT" >&2; exit 2 ;;
esac
if [[ -n "$CHAPTER" && ${#MANUALS[@]} -ne 1 ]]; then
    echo "-c needs exactly one -m manual" >&2; exit 2
fi

if ! command -v typst >/dev/null 2>&1; then
    echo "typst not found; install it (e.g. brew install typst)" >&2
    exit 1
fi

[[ -n "$VERSION" ]] || VERSION="$("$HERE/docs-version.sh")"

# compile SOURCE OUTPUT FORMAT PRODUCT
compile() {
    local src="$1" out="$2" fmt="$3" product="$4"
    local args=(compile --root "$ROOT" --input "product=$product" --input "version=$VERSION")
    if [[ "$fmt" == html ]]; then
        args+=(--features html --format html)
    fi
    typst "${args[@]}" "$src" "$out"
}

if [[ $CHECK -eq 1 ]]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    failures=0
    shopt -s nullglob
    for m in "${MANUALS[@]}"; do
        base="$(manual_dir "$m")"
        dir="$HERE/$base"
        for src in "$dir/$base".[0-9][0-9].typ "$dir/$base".[A-Z].typ "$dir"/deprecated_docs/*.typ; do
            for fmt in pdf html; do
                if ! compile "$src" "$tmp/out.$fmt" "$fmt" openutv >"$tmp/log" 2>&1; then
                    echo "FAIL  ${src#$HERE/} ($fmt)"
                    sed 's/^/      /' "$tmp/log"
                    failures=$((failures + 1))
                fi
            done
        done
    done
    # The Read the Docs build converts the same chapters with a second helper
    # library (rtd/manual-lib-pandoc.typ); building it catches the two
    # drifting apart.
    if ! command -v pandoc >/dev/null 2>&1 || ! command -v sphinx-build >/dev/null 2>&1; then
        echo "skipped Read the Docs build: needs pandoc and sphinx-build (see rtd/README.md)"
    elif "$HERE/rtd/build-rtd.sh" -o "$tmp/rtd" --version "$VERSION" >"$tmp/log" 2>&1; then
        echo "Read the Docs build passes"
    else
        echo "FAIL  rtd/build-rtd.sh"
        sed 's/^/      /' "$tmp/log"
        failures=$((failures + 1))
    fi
    if [[ $failures -eq 0 ]]; then
        echo "all chapters build (pdf + html): ${MANUALS[*]}"
    else
        echo "$failures build(s) failed" >&2
        exit 1
    fi
    exit 0
fi

echo "version $VERSION"
mkdir -p "$OUTDIR"
for m in "${MANUALS[@]}"; do
    base="$(manual_dir "$m")"
    if [[ -n "$CHAPTER" ]]; then
        src="$HERE/$base/$base.$CHAPTER.typ"
        [[ -f "$src" ]] || { echo "no such chapter file: ${src#$HERE/}" >&2; exit 2; }
        stem="$m-manual-chapter-$CHAPTER"
    else
        src="$HERE/$base/$base.typ"
        [[ -f "$src" ]] || { echo "no master file: ${src#$HERE/}" >&2; exit 2; }
        stem="$m-manual"
    fi
    for product in "${PRODUCTS[@]}"; do
        for fmt in "${FORMATS[@]}"; do
            out="$OUTDIR/$product-$stem.$fmt"
            echo "building $out"
            compile "$src" "$out" "$fmt" "$product"
        done
    done
done
