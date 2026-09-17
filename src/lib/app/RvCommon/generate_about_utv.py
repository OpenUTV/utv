#!/usr/bin/env python3
#
# Copyright (C) 2025  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Generate about_utv.cpp with build and dependency information

import argparse
import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path


def get_git_info(git_hash_from_cmake=""):
    """Get git commit hash from CMake"""
    return git_hash_from_cmake if git_hash_from_cmake else "unknown"


def get_pkg_version(pkg_name, brew_name=None):
    try:
        return subprocess.check_output(
            ["pkg-config", "--modversion", pkg_name], stderr=subprocess.DEVNULL, text=True
        ).strip()
    except (subprocess.SubprocessError, OSError):
        if brew_name:
            try:
                out = subprocess.check_output(
                    ["brew", "info", "--json", brew_name], stderr=subprocess.DEVNULL, text=True
                )
                data = json.loads(out)
                return data[0]["versions"]["stable"]
            except (subprocess.SubprocessError, OSError, json.JSONDecodeError, KeyError, IndexError):
                pass
        return "Unknown"


def parse_versions(versions_str):
    """Parse the versions string into a dictionary"""
    versions = {}
    if versions_str:
        for item in versions_str.replace(";", ",").split(","):
            if ":" in item:
                key, value = item.split(":", 1)
                versions[key.strip()] = value.strip()
    return versions


def get_dependencies_info(versions, app_name, platform=""):
    is_commercial_rv = app_name == "RV"
    qt_license = "Qt Commercial" if is_commercial_rv else "LGPL v3"
    pyside_license = "Qt Commercial" if is_commercial_rv else "LGPL v3"

    def resolve_version(name_keys, pkg_name=None, brew_name=None, default=None):
        if isinstance(name_keys, str):
            name_keys = [name_keys]
        for k in name_keys:
            if k in versions and versions[k] and versions[k] != "Unknown":
                return versions[k]
        if pkg_name:
            v = get_pkg_version(pkg_name, brew_name)
            if v and v != "Unknown":
                return v
        return default if default is not None else "Unknown"

    qt_version = resolve_version(["Qt Framework", "Qt", "Qt6", "qt"], "Qt6Core", "qt")
    pyside_version = resolve_version(["PySide", "PySide6", "pyside"], "PySide6", default=qt_version)

    vfx_deps = [
        (
            "Boost",
            resolve_version(["Boost", "boost"], "boost"),
            "Boost Software License",
        ),
        (
            "Imath",
            resolve_version(["Imath", "imath"], "Imath", "imath"),
            "BSD 3-Clause",
        ),
        ("NumPy", resolve_version(["NumPy", "numpy"], default="Installed"), "BSD 3-Clause"),
        (
            "OpenColorIO",
            resolve_version(["OpenColorIO", "opencolorio", "OCIO"], "OpenColorIO", "opencolorio"),
            "BSD 3-Clause",
        ),
        (
            "OpenColorIO ACES Config",
            "4.0.0 (ACES 2.0)",
            "BSD 3-Clause",
        ),
        (
            "OpenEXR",
            resolve_version(["OpenEXR", "openexr"], "OpenEXR", "openexr"),
            "BSD 3-Clause",
        ),
        (
            "OpenImageIO",
            resolve_version(["OpenImageIO", "openimageio", "OIIO"], "OpenImageIO", "openimageio"),
            "Apache 2.0",
        ),
        (
            "OpenTimelineIO",
            resolve_version(["OpenTimelineIO", "opentimelineio", "OTIO"], default="Installed"),
            "Apache 2.0",
        ),
        ("PySide", pyside_version, pyside_license),
        (
            "Python",
            resolve_version(["Python", "python", "Python3"], "python3", "python"),
            "PSF License",
        ),
        ("Qt Framework", qt_version, qt_license),
    ]

    rv_specific_deps = []
    if is_commercial_rv:
        is_macos = "darwin" in platform.lower() or "macos" in platform.lower()
        if is_macos:
            rv_specific_deps.append(("Apple ProRes", "Not Used", "Apple Proprietary"))
        rv_specific_deps.extend(
            [
                ("ARRI SDK", "Not Used", "ARRI Proprietary"),
                ("NDI SDK", "Not Used", "NDI Proprietary"),
                ("RED R3D SDK", "Not Used", "RED Proprietary"),
                ("x264", "Not Used", "x264 Commercial License"),
            ]
        )

    other_deps = [
        (
            "AJA NTV2 SDK",
            resolve_version(["AJA NTV2 SDK", "AJA", "aja"]),
            "MIT License",
        ),
        (
            "Blackmagic DeckLink SDK",
            resolve_version(["Blackmagic DeckLink SDK", "BMD", "bmd"]),
            "Proprietary",
        ),
        (
            "Blackmagic RAW SDK",
            resolve_version(["Blackmagic RAW", "BRAW", "braw"], default="Dynamic (System)"),
            "MIT-style",
        ),
        (
            "Boehm GC",
            resolve_version(["Boehm GC", "bdw-gc", "gc"], "bdw-gc", "bdw-gc"),
            "MIT-style",
        ),
        ("dav1d", resolve_version(["dav1d"], "dav1d", "dav1d"), "BSD 2-Clause"),
        ("Dear ImGui", resolve_version(["Dear ImGui", "imgui"], default="Installed"), "MIT License"),
        (
            "Expat",
            resolve_version(["Expat", "expat"], "expat", "expat"),
            "MIT License",
        ),
        (
            "FFmpeg",
            resolve_version(["FFmpeg", "ffmpeg", "libavcodec"], "libavcodec", "ffmpeg"),
            "LGPL v2.1+",
        ),
        (
            "GLEW",
            resolve_version(["GLEW", "glew"], "glew", "glew"),
            "Modified BSD / MIT",
        ),
        (
            "libjpeg-turbo",
            resolve_version(["libjpeg-turbo", "jpeg-turbo", "jpegturbo"], "libturbojpeg", "jpeg-turbo"),
            "BSD-style",
        ),
        (
            "libpng",
            resolve_version(["libpng"], "libpng", "libpng"),
            "libpng License",
        ),
        (
            "LibRaw",
            resolve_version(["LibRaw", "libraw", "raw"], "libraw", "libraw"),
            "LGPL v2.1 / CDDL",
        ),
        (
            "libspng",
            resolve_version(["libspng", "spng"], "libspng"),
            "BSD 2-Clause",
        ),
        (
            "libtiff",
            resolve_version(["libtiff", "tiff"], "libtiff-4", "libtiff"),
            "libtiff License",
        ),
        (
            "libwebp",
            resolve_version(["libwebp", "webp"], "libwebp", "webp"),
            "BSD 3-Clause",
        ),
        ("nanobind", resolve_version(["nanobind"], default="Installed"), "BSD 3-Clause"),
        (
            "OpenJPEG",
            resolve_version(["OpenJPEG", "openjpeg"], "libopenjp2", "openjpeg"),
            "BSD 2-Clause",
        ),
        ("OpenJPH", resolve_version(["OpenJPH", "openjph"]), "BSD 2-Clause"),
        (
            "OpenSSL",
            resolve_version(["OpenSSL", "openssl"], "openssl", "openssl"),
            "Apache License 2.0",
        ),
        (
            "PCRE2",
            resolve_version(["PCRE2", "pcre2"], "libpcre2-8", "pcre2"),
            "BSD License",
        ),
        (
            "RED R3D SDK",
            resolve_version(["RED R3D SDK", "RED", "red", "R3D"], default="Dynamic (IPP2)"),
            "Proprietary",
        ),
        ("spdlog", resolve_version(["spdlog"], "spdlog", "spdlog"), "MIT License"),
        (
            "yaml-cpp",
            resolve_version(["yaml-cpp", "yaml"], "yaml-cpp", "yaml-cpp"),
            "MIT License",
        ),
        ("zlib", resolve_version(["zlib"], "zlib", "zlib"), "zlib License"),
    ]

    return vfx_deps, other_deps, rv_specific_deps


def generate_about_cpp(
    output_file,
    compiler,
    vfx_platform,
    platform,
    arch,
    app_name,
    versions_str="",
    git_hash="",
):
    """Generate the about_utv.cpp file"""

    git_commit = get_git_info(git_hash)
    versions = parse_versions(versions_str)
    vfx_deps, other_deps, rv_specific_deps = get_dependencies_info(versions, app_name, platform)
    build_date = datetime.now(UTC).strftime("%B %d, %Y")

    # Build the HTML content
    html_content = []
    html_content.append("<p>")
    html_content.append(f"<b>{platform} {arch}</b>")
    html_content.append("</p>")
    html_content.append("<p>")
    html_content.append(f"Compiled using <b>{compiler}</b>")
    html_content.append("</p>")
    html_content.append("<p>")
    html_content.append(f"Build identifier: {app_name}, HEAD={git_commit}")
    html_content.append("</p>")
    html_content.append("<p>")
    html_content.append(f"Built on: {build_date}")
    html_content.append("</p>")

    # Single table with both sections
    html_content.append("<p><hr></p>")
    html_content.append("<p>")
    html_content.append('<table border="0" cellpadding="4" cellspacing="0" width="100%">')

    # VFX Platform header row
    if vfx_platform:
        # Extract year from platform (e.g., "CY2024" -> "2024")
        vfx_year = vfx_platform.replace("CY", "") if vfx_platform.startswith("CY") else vfx_platform
        html_content.append("<tr>")
        html_content.append(f'<td colspan="3"><b>VFX Reference Platform {vfx_year}</b></td>')
        html_content.append("</tr>")

        # Column headers
        html_content.append("<tr>")
        html_content.append("<td><b>Description</b></td>")
        html_content.append("<td><b>Version</b></td>")
        html_content.append("<td><b>License</b></td>")
        html_content.append("</tr>")

        # VFX Platform dependencies
        for desc, version, license in vfx_deps:
            html_content.append("<tr>")
            html_content.append(f"<td>{desc}</td>")
            html_content.append(f"<td>{version}</td>")
            html_content.append(f"<td>{license}</td>")
            html_content.append("</tr>")

        # Empty row separator
        html_content.append('<tr><td colspan="3">&nbsp;</td></tr>')

    # Other Dependencies header row
    html_content.append("<tr>")
    html_content.append('<td colspan="3"><b>Other Dependencies</b></td>')
    html_content.append("</tr>")

    # Column headers for other dependencies
    html_content.append("<tr>")
    html_content.append("<td><b>Description</b></td>")
    html_content.append("<td><b>Version</b></td>")
    html_content.append("<td><b>License</b></td>")
    html_content.append("</tr>")

    # Other dependencies
    for desc, version, license in other_deps:
        html_content.append("<tr>")
        html_content.append(f"<td>{desc}</td>")
        html_content.append(f"<td>{version}</td>")
        html_content.append(f"<td>{license}</td>")
        html_content.append("</tr>")

    # RV-Specific Components section (only for commercial RV)
    if rv_specific_deps:
        # Empty row separator
        html_content.append('<tr><td colspan="3">&nbsp;</td></tr>')

        # RV Components header row
        html_content.append("<tr>")
        html_content.append('<td colspan="3"><b>RV-Specific Components</b></td>')
        html_content.append("</tr>")

        # Column headers
        html_content.append("<tr>")
        html_content.append("<td><b>Description</b></td>")
        html_content.append("<td><b>Version</b></td>")
        html_content.append("<td><b>License</b></td>")
        html_content.append("</tr>")

        # RV-specific components
        for desc, version, license in rv_specific_deps:
            html_content.append("<tr>")
            html_content.append(f"<td>{desc}</td>")
            html_content.append(f"<td>{version}</td>")
            html_content.append(f"<td>{license}</td>")
            html_content.append("</tr>")

    html_content.append("</table>")
    html_content.append("</p>")
    html_content.append("<p><hr></p>")
    html_content.append("<p>")
    html_content.append("For detailed license information, please see the THIRD-PARTY.md file ")
    html_content.append("included with this distribution or visit the UTV GitHub repository.")
    html_content.append("</p>")

    # Join without newlines - HTML doesn't need them
    html_str = "".join(html_content)

    # Escape quotes for C++
    html_str = html_str.replace('"', '\\"')

    # Generate the C++ file
    cpp_content = f'''//
// Copyright (C) 2025  Autodesk, Inc. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
// This file is auto-generated by generate_about_utv.py
// DO NOT EDIT MANUALLY

const char* about_UTV = "{html_str}";
'''

    # Ensure the output directory exists
    try:
        output_path = Path(output_file)
        print(f"Creating directory: {output_path.parent}")
        output_path.parent.mkdir(parents=True, exist_ok=True)

        with open(output_file, "w", encoding="utf-8", newline="\n") as f:
            f.write(cpp_content)

        # Verify the file was written
        if not output_path.exists():
            print(f"ERROR: File was not created: {output_file}", file=sys.stderr)
            sys.exit(1)

        file_size = output_path.stat().st_size
        print(f"Generated {output_file} ({file_size} bytes)")

    except (OSError, ValueError) as e:
        print(f"ERROR generating {output_file}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate about_utv.cpp with build and dependency information")
    parser.add_argument("output_file", help="Path to the output C++ file")
    parser.add_argument("compiler", help="Compiler name and version")
    parser.add_argument("vfx_platform", help="VFX Platform version (e.g., CY2024)")
    parser.add_argument("platform", help="Target platform (e.g., macOS, Linux, Windows)")
    parser.add_argument("arch", help="Target architecture (e.g., x86_64, arm64)")
    parser.add_argument("app_name", nargs="?", default="UTV", help="Application name")
    parser.add_argument("versions", nargs="?", default="", help="Comma-separated dependency versions")
    parser.add_argument("git_hash", nargs="?", default="", help="Git commit hash")

    args = parser.parse_args()

    print(f"=== generate_about_utv.py: generating {args.output_file} ===", flush=True)
    generate_about_cpp(
        args.output_file,
        args.compiler,
        args.vfx_platform,
        args.platform,
        args.arch,
        args.app_name,
        args.versions,
        args.git_hash,
    )
