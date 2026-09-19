#!/usr/bin/env python3
#
# Sanitize Homebrew Links for UTV
# Converts /opt/homebrew/Cellar/... links to /opt/homebrew/opt/...
# Copyright (C) 2026 Makai Systems. All Rights Reserved.
#

import os
import sys
import subprocess
import pathlib
import re

BREW_PREFIX = os.environ.get("HOMEBREW_PREFIX", "/opt/homebrew" if os.uname().machine == "arm64" else "/usr/local")
CELLAR_PATTERN = re.compile(rf"{re.escape(BREW_PREFIX)}/Cellar/([^/]+)/[^/]+/(.+)")


def get_dependencies(binary_path):
    try:
        output = subprocess.check_output(["otool", "-L", binary_path], text=True)
        # Skip first line (the binary itself)
        deps = []
        for line in output.splitlines()[1:]:
            parts = line.strip().split()
            if parts:
                deps.append(parts[0])
        return deps
    except Exception:
        return []


def sanitize_binary(binary_path):
    print(f"--- Sanitizing: {os.path.basename(binary_path)}")
    deps = get_dependencies(binary_path)
    changed = False

    for dep in deps:
        current_dep = dep

        # 1. Map /Cellar/<pkg>/<ver>/... paths to /opt/<pkg>/...
        match = CELLAR_PATTERN.match(current_dep)
        if match:
            pkg_name = match.group(1)
            remaining_path = match.group(2)
            stable_path = f"{BREW_PREFIX}/opt/{pkg_name}/{remaining_path}"

            # Verify stable path exists
            if os.path.exists(stable_path):
                print(f"  Mapping Cellar link: {current_dep} -> {stable_path}")
                try:
                    subprocess.check_call(["install_name_tool", "-change", current_dep, stable_path, binary_path])
                    changed = True
                    current_dep = stable_path
                except subprocess.CalledProcessError as e:
                    print(f"  Error changing link: {e}")
            else:
                print(f"  Warning: Stable path {stable_path} not found for {current_dep}")

        # 2. Map versioned OpenJPH dylib (e.g. libopenjph.0.31.dylib) to unversioned symlink (libopenjph.dylib)
        # This ensures OpenUTV remains compatible across Homebrew OpenJPH minor version updates
        if "openjph" in current_dep and re.search(r"libopenjph\.[0-9.]+\.dylib", current_dep):
            unversioned_jph = f"{BREW_PREFIX}/opt/openjph/lib/libopenjph.dylib"
            if os.path.exists(unversioned_jph):
                print(f"  Mapping OpenJPH versioned link: {current_dep} -> {unversioned_jph}")
                try:
                    subprocess.check_call(["install_name_tool", "-change", current_dep, unversioned_jph, binary_path])
                    changed = True
                    current_dep = unversioned_jph
                except subprocess.CalledProcessError as e:
                    print(f"  Error changing OpenJPH link: {e}")

    return changed


def main():
    if len(sys.argv) < 2:
        print("Usage: sanitize_homebrew_links.py <path_to_search>")
        sys.exit(1)

    search_path = pathlib.Path(sys.argv[1])
    if not search_path.exists():
        print(f"Error: Path {search_path} does not exist.")
        sys.exit(1)

    print(f"Scanning for binaries in: {search_path}")

    count = 0
    for root, _, files in os.walk(search_path):
        for f in files:
            full_path = os.path.join(root, f)

            # Basic check for Mach-O binaries
            try:
                file_info = subprocess.check_output(["file", "-b", full_path], text=True)
                if "Mach-O" in file_info:
                    if sanitize_binary(full_path):
                        count += 1
            except Exception:
                continue

    print(f"Done. Sanitized {count} binaries.")


if __name__ == "__main__":
    main()
