#!/usr/bin/env python3
#
# Copyright (C) 2026  Makai Systems. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
"""Remove build-only files from a staged app before it is packaged.

The macOS and Linux packages are made from the stage directory
(_build/stage/app), not from `cmake --install`, so they skip the filter in
cmake/install/pre_install.cmake that leaves out static libraries, libtool and
qmake leftovers, object files and test programs. This applies the same filter
to the stage directory. Run it after the tests (they use the test programs)
and, on macOS, before signing.

Usage: prune_package.py <UTV.app or stage directory> [--dry-run]
"""

import argparse
import os
import re
import shutil
import sys

# Files nothing loads at run time.
BUILD_ONLY_SUFFIXES = (".a", ".la", ".prl", ".o", ".obj")

# Directories of build metadata under lib/.
BUILD_ONLY_LIB_DIRS = ("cmake", "pkgconfig")

# Test programs in bin/ (Linux: a launcher script plus <name>.bin) or
# Contents/MacOS/, as in pre_install.cmake. Qt's own QtTest libraries live in
# lib/ and are not touched.
TEST_PROGRAM = re.compile(r"^[A-Za-z0-9_]*Test(\.bin)?$")
PROGRAM_DIRS = ("bin", "MacOS")


def prune(root, dry_run):
    removed = []

    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        parts = rel.split(os.sep)

        if parts[-1] == "lib":
            for d in list(dirnames):
                if d in BUILD_ONLY_LIB_DIRS:
                    path = os.path.join(dirpath, d)
                    removed.append((path, tree_size(path)))
                    dirnames.remove(d)
                    if not dry_run:
                        shutil.rmtree(path)

        in_program_dir = parts[-1] in PROGRAM_DIRS
        for f in filenames:
            path = os.path.join(dirpath, f)
            if os.path.islink(path):
                continue
            if f.endswith(BUILD_ONLY_SUFFIXES) or (in_program_dir and TEST_PROGRAM.match(f)):
                removed.append((path, os.path.getsize(path)))
                if not dry_run:
                    os.remove(path)

    return removed


def tree_size(path):
    total = 0
    for dirpath, _, filenames in os.walk(path):
        for f in filenames:
            p = os.path.join(dirpath, f)
            if not os.path.islink(p):
                total += os.path.getsize(p)
    return total


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("root", help="UTV.app or the stage directory")
    parser.add_argument("--dry-run", action="store_true", help="list what would be removed")
    args = parser.parse_args()

    if not os.path.isdir(args.root):
        sys.exit(f"prune_package: {args.root} is not a directory")

    removed = prune(args.root, args.dry_run)
    total = sum(size for _, size in removed)
    verb = "Would remove" if args.dry_run else "Removed"
    for path, size in sorted(removed, key=lambda r: -r[1])[:15]:
        print(f"  {size / 1048576:7.1f} MB  {os.path.relpath(path, args.root)}")
    print(f"{verb} {len(removed)} build-only files ({total / 1048576:.0f} MB) from {args.root}")


if __name__ == "__main__":
    main()
