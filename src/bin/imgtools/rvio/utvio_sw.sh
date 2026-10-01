#!/bin/sh
#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
# utvio_sw / rvio_sw: utvio with software rendering and no X display, for render nodes and
# containers without a GPU. Replaces the OSMesa-based rvio_sw (OSMesa was removed from Mesa 25.1):
# utvio renders through an EGL context with no window system, using Mesa's llvmpipe.
#
# Plain utvio already uses EGL when DISPLAY is unset and will use a GPU if the node has one; use
# this command to force software rendering regardless of the machine.
#

self=$(readlink -f "$0")
bindir=$(dirname "$self")

UTV_GL_PLATFORM=egl
LIBGL_ALWAYS_SOFTWARE=1
export UTV_GL_PLATFORM LIBGL_ALWAYS_SOFTWARE

exec "$bindir/utvio" "$@"
