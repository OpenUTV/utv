#!/usr/bin/env python3
#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Generate synthetic test media for UTV on demand. Run with --help, or see README.md next to this file."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from testmedia.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
