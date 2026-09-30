#!/usr/bin/env python3
#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Verify that no Mach-O binary in an app bundle requires a newer macOS than the bundle declares.

Reads LSMinimumSystemVersion from <bundle>/Contents/Info.plist (or --min-version) and fails if any
executable, dylib, or Python extension reports a higher LC_BUILD_VERSION minos. This catches builds
that silently inherit the build host's macOS version as their minimum.

Usage: check_macos_min_version.py path/to/UTV.app [--min-version 15.0]
"""

import argparse
import os
import plistlib
import subprocess
import sys

MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce",
    b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf",
    b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe",  # universal
}


def parse_version(text):
    return tuple(int(part) for part in text.strip().split("."))


def is_macho(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) in MACHO_MAGICS
    except OSError:
        return False


def binary_min_versions(path):
    """Return the set of minos versions reported by otool for each architecture slice."""
    result = subprocess.run(["otool", "-l", path], capture_output=True, text=True, check=False)
    versions = set()
    lines = result.stdout.splitlines()
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "cmd LC_BUILD_VERSION":
            for follow in lines[i + 1 : i + 6]:
                parts = follow.split()
                if len(parts) == 2 and parts[0] == "minos":
                    versions.add(parts[1])
                    break
        elif stripped == "cmd LC_VERSION_MIN_MACOSX":
            for follow in lines[i + 1 : i + 4]:
                parts = follow.split()
                if len(parts) == 2 and parts[0] == "version":
                    versions.add(parts[1])
                    break
    return versions


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("bundle", help="Path to the .app bundle")
    parser.add_argument(
        "--min-version", help="Override the declared minimum (default: Info.plist LSMinimumSystemVersion)"
    )
    args = parser.parse_args()

    declared = args.min_version
    if not declared:
        plist_path = os.path.join(args.bundle, "Contents", "Info.plist")
        with open(plist_path, "rb") as f:
            declared = plistlib.load(f).get("LSMinimumSystemVersion")
        if not declared:
            print(f"ERROR: {plist_path} has no LSMinimumSystemVersion", file=sys.stderr)
            return 1

    limit = parse_version(declared)
    checked = 0
    offenders = []

    for root, _dirs, files in os.walk(args.bundle):
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path) or not is_macho(path):
                continue
            checked += 1
            for minos in binary_min_versions(path):
                if parse_version(minos) > limit:
                    offenders.append((minos, os.path.relpath(path, args.bundle)))

    if offenders:
        print(
            f"ERROR: {len(offenders)} binaries require a newer macOS than the declared minimum {declared}:",
            file=sys.stderr,
        )
        for minos, rel in sorted(offenders):
            print(f"  minos {minos}  {rel}", file=sys.stderr)
        return 1

    print(f"OK: all {checked} Mach-O binaries in {args.bundle} support macOS {declared}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
