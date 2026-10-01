#!/usr/bin/env python3
#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Smoke test the bundled command line tools.

Each tool must start, resolve its runtime dependencies, and exit within a timeout with the expected
output. A missing shared library, Qt platform plugin, or Python home shows up here as a crash, a
loader error, or a hang instead of in front of a user.

On Windows the .cmd wrappers are preferred over the raw .exe files, since that is what users run.

Usage: cli_smoke.py --bin-dir <staged bin dir> [--timeout 60]
"""

import argparse
import os
import re
import sys

from cli_common import find_tool, prepare_environment, run_tool

# Known platform-specific failures tracked in an issue: reported as xfail (not a test failure), or XPASS
# once fixed so the entry can be removed.
KNOWN_FAILURES = {}

# (tool, args, require exit code 0, regex that must appear in stdout+stderr)
CHECKS = [
    ("utvio", ["-version"], True, r"^\d{4}\.\d+"),
    ("utvls", ["-version"], True, r"^\d{4}\.\d+"),
    ("utvpkg", ["-list"], True, r"\.rvpkg"),
    ("utvpush", ["-help"], False, r"usage: rvpush"),
    ("utvshell", ["-help"], False, r"usage: rvshell"),
    ("utvprof", ["-help"], False, r"usage: rvprof"),
    ("py-interp", ["-c", "import json, ssl, sqlite3; print('py-interp-ok')"], True, r"py-interp-ok"),
    ("openutv-diagnostics", ["--help"], True, r"Usage: openutv-diagnostics"),
    ("openutv-check-updates", ["--help"], True, r"Usage: openutv-check-updates"),
]

if sys.platform.startswith("linux"):
    # Software-rendering, display-less launcher (and its legacy rvio_sw name).
    CHECKS += [
        ("utvio_sw", ["-version"], True, r"^\d{4}\.\d+"),
        ("rvio_sw", ["-version"], True, r"^\d{4}\.\d+"),
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bin-dir", required=True, help="Staged application bin directory")
    parser.add_argument("--timeout", type=int, default=60, help="Per-command timeout in seconds")
    args = parser.parse_args()

    env = prepare_environment()
    failures = []

    for tool, tool_args, need_zero, pattern in CHECKS:
        path = find_tool(args.bin_dir, tool)
        if not path:
            failures.append(f"{tool}: not found in {args.bin_dir}")
            print(f"FAIL {tool}: not found")
            continue

        result = run_tool([path] + tool_args, env, args.timeout)
        problems = []
        if result.timed_out:
            problems.append(f"timed out after {args.timeout}s")
        elif result.crashed:
            problems.append(f"crashed (exit {result.returncode})")
        elif need_zero and result.returncode != 0:
            problems.append(f"exit code {result.returncode}")
        if not result.timed_out and not re.search(pattern, result.output, re.MULTILINE):
            problems.append(f"output did not match /{pattern}/")

        label = f"{os.path.basename(path)} {' '.join(tool_args)}"
        known = KNOWN_FAILURES.get(tool)
        if problems and known:
            print(f"xfail {label}: {', '.join(problems)} (known: {known})")
        elif known:
            print(f"XPASS {label}: passes now, remove it from KNOWN_FAILURES ({known})")
        elif problems:
            failures.append(f"{label}: {', '.join(problems)}")
            print(f"FAIL {label}: {', '.join(problems)}")
            print("  --- output (last 20 lines) ---")
            for line in result.output.splitlines()[-20:]:
                print(f"  {line}")
        else:
            print(f"ok   {label}")

    if failures:
        print(f"\n{len(failures)} of {len(CHECKS)} CLI checks failed")
        return 1
    print(f"\nAll {len(CHECKS)} CLI checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
