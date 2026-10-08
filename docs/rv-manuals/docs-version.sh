#!/usr/bin/env bash
#
# Print the version the manuals show (title page, PDF footer, HTML title,
# Read the Docs sidebar). build-docs.sh and rtd/build-rtd.sh use it unless
# given --version. Works out the version the way CMakeLists.txt does:
#
#   1. a Read the Docs build of a tag: that tag
#   2. the source is exactly at a release tag: the tag          2026.8
#   3. after a release tag: tag + "+dev" and the commit         2026.8+dev (ec5dd1d)
#   4. no tags (e.g. a fork): CMakeLists.txt's version + "+dev" 2026.7+dev (ec5dd1d)
#
# A leading "v" on a tag is dropped.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ "${READTHEDOCS_VERSION_TYPE:-}" == tag && -n "${READTHEDOCS_VERSION_NAME:-}" ]]; then
    echo "${READTHEDOCS_VERSION_NAME#v}"
    exit 0
fi

commit=""
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if tag="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null)"; then
        echo "${tag#v}"
        exit 0
    fi
    commit=" ($(git -C "$ROOT" rev-parse --short HEAD))"
    if tag="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null)"; then
        echo "${tag#v}+dev$commit"
        exit 0
    fi
fi

# same variables the build reads: SET(RV_MAJOR_VERSION "2026" CACHE ...)
cmake_var() {
    sed -n "s/^SET(RV_$1 \"\([0-9]*\)\".*/\1/p" "$ROOT/CMakeLists.txt" | head -1
}
major="$(cmake_var MAJOR_VERSION)"
minor="$(cmake_var MINOR_VERSION)"
if [[ -z "$major" || -z "$minor" ]]; then
    echo "development$commit"
else
    echo "$major.$minor+dev$commit"
fi
