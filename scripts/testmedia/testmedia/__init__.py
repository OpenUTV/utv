#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""On-demand synthetic test media for UTV: codecs, containers, image formats, EXR features and corrupt files."""

# Importing the recipe modules registers their recipes. corrupt must come last: it builds on the others.
from . import video, sequences, exr, corrupt  # noqa: F401,E401
