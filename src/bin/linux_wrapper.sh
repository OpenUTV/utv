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
# then the dependency prefix (UTV_DEPS_ROOT, or Homebrew on Linux). Homebrew keeps each formula's
# libraries in opt/<formula>/lib, which is where UTV's dependency links point.
#
# The graphics driver stack must come from the system: Homebrew installs its own Mesa (and libdrm,
# LLVM, ...) as dependencies of glew, and putting those first would replace the user's GPU driver
# (e.g. NVIDIA's libGL) with Homebrew's software Mesa. So the prefix's combined lib/ directory is
# not used, and these formulas are skipped.
libpath="$UTV_HOME/lib"
if [ -z "$RV_USE_SYSTEM_OPENSSL" ] && [ -d "$UTV_HOME/lib/OpenSSL" ]; then
    libpath="$libpath:$UTV_HOME/lib/OpenSSL"
fi

deps=${UTV_DEPS_ROOT:-${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}}
if [ -d "$deps/opt" ]; then
    for keg in "$deps"/opt/*; do
        case "$(basename "$keg")" in
        mesa | libglvnd | libdrm | llvm | llvm@* | libpciaccess | libxshmfence) continue ;;
        esac
        for keglib in "$keg/lib" "$keg/lib64"; do
            [ -d "$keglib" ] && libpath="$libpath:$keglib"
        done
    done
elif [ -d "$deps/lib" ]; then
    # A plain prefix without Homebrew's opt/ layout.
    libpath="$libpath:$deps/lib"
fi

# Preload the system's GL libraries. Homebrew libraries carry a RUNPATH to the Homebrew prefix, so
# without this a reference to libGL.so.1 from e.g. libGLEW or Qt can still resolve to Homebrew's Mesa.
# Shared libraries are reused by soname once loaded, so preloading pins every user to the system
# driver. Set UTV_NO_SYSTEM_GL_PRELOAD=1 to disable.
if [ -z "$UTV_NO_SYSTEM_GL_PRELOAD" ]; then
    ldconfig_bin=$(command -v ldconfig || echo /sbin/ldconfig)
    for gllib in libGL.so.1 libEGL.so.1; do
        syslib=$("$ldconfig_bin" -p 2>/dev/null | awk -v lib="$gllib" '$1 == lib { print $NF; exit }')
        [ -n "$syslib" ] && LD_PRELOAD="$syslib${LD_PRELOAD:+:$LD_PRELOAD}"
    done
    export LD_PRELOAD
fi

LD_LIBRARY_PATH="$libpath${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
PATH="$bindir:$PATH"
export LD_LIBRARY_PATH PATH
unset BUILD_ROOT

exec "$bin" "$@"
