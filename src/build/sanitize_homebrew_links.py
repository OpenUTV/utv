#!/usr/bin/env python3
#
# Sanitize Dynamic Library Links for UTV
# Ensures generic unversioned dynamic library links across packages:
# - macOS: Converts /opt/homebrew/Cellar/... links to /opt/homebrew/opt/...
#   and versioned dylibs (e.g. libOpenEXR-3_4.33.dylib, libImath-3_2.30.dylib)
#   to unversioned symlinks (e.g. libOpenEXR.dylib, libImath.dylib) via install_name_tool.
# - Linux: Converts versioned SONAMEs (e.g. libOpenEXR-3_4.so.33) to
#   unversioned names (libOpenEXR.so) via patchelf if available.
#
# Copyright (C) 2026 Makai Systems. All Rights Reserved.
#

import os
import sys
import subprocess
import pathlib
import re

DEFAULT_BREW_PREFIX = (
    "/opt/homebrew"
    if (sys.platform == "darwin" and os.uname().machine == "arm64")
    else ("/home/linuxbrew/.linuxbrew" if sys.platform.startswith("linux") else "/usr/local")
)
BREW_PREFIX = os.environ.get("HOMEBREW_PREFIX", DEFAULT_BREW_PREFIX)
CELLAR_PATTERN = re.compile(rf"{re.escape(BREW_PREFIX)}/Cellar/([^/]+)/[^/]+/(.+)")

# System libraries that should never be renamed on Linux
LINUX_SYSTEM_LIBS = {
    "libc.so",
    "libm.so",
    "libdl.so",
    "libpthread.so",
    "librt.so",
    "libstdc++.so",
    "libgcc_s.so",
    "ld-linux",
}


def get_dependencies_macho(binary_path):
    try:
        output = subprocess.check_output(["otool", "-L", binary_path], text=True)
        deps = []
        for line in output.splitlines()[1:]:
            parts = line.strip().split()
            if parts:
                deps.append(parts[0])
        return deps
    except Exception:
        return []


def sanitize_macho_binary(binary_path):
    deps = get_dependencies_macho(binary_path)
    changed = False

    for dep in deps:
        current_dep = dep

        # 1. Map /Cellar/<pkg>/<ver>/... paths to /opt/<pkg>/...
        match = CELLAR_PATTERN.match(current_dep)
        if match:
            pkg_name = match.group(1)
            remaining_path = match.group(2)
            stable_path = f"{BREW_PREFIX}/opt/{pkg_name}/{remaining_path}"

            if os.path.exists(stable_path):
                print(f"  [{os.path.basename(binary_path)}] Mapping Cellar link: {current_dep} -> {stable_path}")
                try:
                    subprocess.check_call(["install_name_tool", "-change", current_dep, stable_path, binary_path])
                    changed = True
                    current_dep = stable_path
                except subprocess.CalledProcessError as e:
                    print(f"  [{os.path.basename(binary_path)}] Error changing Cellar link: {e}")
            else:
                # If stable path does not exist as-is, check if remaining_path has versioned dylib
                base = os.path.basename(remaining_path)
                generic_base = re.sub(r"(-[0-9_]+|\.[0-9]+).*\.dylib$", ".dylib", base)
                alt_path = f"{BREW_PREFIX}/opt/{pkg_name}/lib/{generic_base}"
                if os.path.exists(alt_path):
                    print(f"  [{os.path.basename(binary_path)}] Mapping Cellar link: {current_dep} -> {alt_path}")
                    try:
                        subprocess.check_call(["install_name_tool", "-change", current_dep, alt_path, binary_path])
                        changed = True
                        current_dep = alt_path
                    except subprocess.CalledProcessError as e:
                        print(f"  [{os.path.basename(binary_path)}] Error changing Cellar link: {e}")

        # 2. Map versioned dylibs (e.g. libOpenEXR-3_4.33.dylib, libImath-3_2.30.dylib, libopenjph.0.31.dylib)
        # to generic unversioned symlinks (e.g. libOpenEXR.dylib, libImath.dylib, libopenjph.dylib).
        # This ensures OpenUTV remains compatible across package manager minor updates.
        if current_dep.startswith(BREW_PREFIX) or "/opt/" in current_dep or "/Cellar/" in current_dep:
            dir_name = os.path.dirname(current_dep)
            base_name = os.path.basename(current_dep)
            generic_name = re.sub(r"(-[0-9_]+|\.[0-9]+).*\.dylib$", ".dylib", base_name)

            if generic_name != base_name:
                generic_path = os.path.join(dir_name, generic_name)
                # If dir_name was inside a Cellar version folder, redirect to opt
                if "/Cellar/" in generic_path:
                    generic_path = re.sub(
                        rf"{re.escape(BREW_PREFIX)}/Cellar/([^/]+)/[^/]+/",
                        rf"{BREW_PREFIX}/opt/\1/",
                        generic_path,
                    )

                if os.path.exists(generic_path) or os.path.exists(os.path.dirname(generic_path)):
                    print(
                        f"  [{os.path.basename(binary_path)}] Mapping to generic dylib link: {current_dep} -> {generic_path}"
                    )
                    try:
                        subprocess.check_call(["install_name_tool", "-change", current_dep, generic_path, binary_path])
                        changed = True
                        current_dep = generic_path
                    except subprocess.CalledProcessError as e:
                        print(f"  [{os.path.basename(binary_path)}] Error changing generic link: {e}")

    return changed


def sanitize_elf_binary(binary_path):
    if not hasattr(sanitize_elf_binary, "patchelf_available"):
        sanitize_elf_binary.patchelf_available = (
            subprocess.call(["which", "patchelf"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0
        )

    if not sanitize_elf_binary.patchelf_available:
        return False

    try:
        output = subprocess.check_output(["patchelf", "--print-needed", binary_path], text=True)
        needed_libs = [line.strip() for line in output.splitlines() if line.strip()]
    except Exception:
        return False

    changed = False
    for lib in needed_libs:
        # Skip glibc and system standard libraries
        if any(sys_lib in lib for sys_lib in LINUX_SYSTEM_LIBS):
            continue

        generic_lib = re.sub(r"(-[0-9_]+|\.so\.[0-9]+|\.[0-9]+).*", ".so", lib)
        if generic_lib != lib and generic_lib.endswith(".so"):
            print(f"  [{os.path.basename(binary_path)}] Mapping needed ELF lib: {lib} -> {generic_lib}")
            try:
                subprocess.check_call(["patchelf", "--replace-needed", lib, generic_lib, binary_path])
                changed = True
            except subprocess.CalledProcessError as e:
                print(f"  [{os.path.basename(binary_path)}] Error replacing needed library {lib}: {e}")

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
    for root, dirs, files in os.walk(search_path):
        # Skip Python site-packages in app/lib to keep execution fast
        if "site-packages" in root:
            continue

        for f in files:
            full_path = os.path.join(root, f)

            # Skip symlinks
            if os.path.islink(full_path):
                continue

            # Basic check for Mach-O or ELF binaries
            try:
                file_info = subprocess.check_output(["file", "-b", full_path], text=True)
                if "Mach-O" in file_info:
                    if sanitize_macho_binary(full_path):
                        count += 1
                elif "ELF" in file_info:
                    if sanitize_elf_binary(full_path):
                        count += 1
            except Exception:
                continue

    print(f"Done. Sanitized {count} binaries.")


if __name__ == "__main__":
    main()
