#!/bin/sh
#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Linux launcher installed in place of each executable by rv_stage(); the real
# binary sits next to it as <name>.bin. Sets up the library path and execs it.
#
# Symlinks (e.g. rvio -> utvio) are resolved so the real name and location are used.
#

self=$(readlink -f "$0")
name=$(basename "$self")
bindir=$(dirname "$self")

bin="$bindir/$name.bin"
if [ ! -x "$bin" ]; then
    echo "ERROR: $bin not found" >&2
    exit 1
fi

UTV_HOME=${UTV_HOME:-${RV_HOME:-$(dirname "$bindir")}}
RV_HOME=${RV_HOME:-$UTV_HOME}
export UTV_HOME RV_HOME

# Library path: UTV's own libraries, the bundled OpenSSL unless RV_USE_SYSTEM_OPENSSL is set,
# then the dependency prefix (UTV_DEPS_ROOT, or Homebrew on Linux). Homebrew keeps formula
# libraries in opt/<formula>/lib, which is where UTV's dependency links point.
libpath="$UTV_HOME/lib"
if [ -z "$RV_USE_SYSTEM_OPENSSL" ] && [ -d "$UTV_HOME/lib/OpenSSL" ]; then
    libpath="$libpath:$UTV_HOME/lib/OpenSSL"
fi

deps=${UTV_DEPS_ROOT:-${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}}
if [ -d "$deps/lib" ]; then
    libpath="$libpath:$deps/lib"
    for keglib in "$deps"/opt/*/lib; do
        [ -d "$keglib" ] && libpath="$libpath:$keglib"
    done
fi

LD_LIBRARY_PATH="$libpath${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
PATH="$bindir:$PATH"
export LD_LIBRARY_PATH PATH
unset BUILD_ROOT

exec "$bin" "$@"
