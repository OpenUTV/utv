#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import argparse
import pathlib
import subprocess


def get_packages_from_dir(packages_source_folder: pathlib.Path) -> [pathlib.Path]:
    for file in sorted(packages_source_folder.iterdir()):
        if file.is_file() and file.suffix == ".rvpkg":
            yield file.resolve()


def install_rvpkg_packages(
    *, rvpkg_path: pathlib.Path, packages_source_folder: pathlib.Path, packages_destination_folder: pathlib.Path
) -> None:
    import os

    env = dict(os.environ)
    # Stage directory: rvpkg is located in <stage>/bin/rvpkg, so parent.parent is <stage>
    stage_dir = rvpkg_path.resolve().parent.parent
    lib_candidates = [
        str(stage_dir / "lib"),
        str(stage_dir / "lib64"),
        "/home/linuxbrew/.linuxbrew/lib",
    ]
    existing_ld = env.get("LD_LIBRARY_PATH", "")
    if existing_ld:
        lib_candidates.append(existing_ld)
    env["LD_LIBRARY_PATH"] = ":".join(p for p in lib_candidates if p)

    existing_dyld = env.get("DYLD_FALLBACK_LIBRARY_PATH", "")
    dyld_candidates = [str(stage_dir / "lib"), str(stage_dir / "Frameworks")]
    if existing_dyld:
        dyld_candidates.append(existing_dyld)
    env["DYLD_FALLBACK_LIBRARY_PATH"] = ":".join(p for p in dyld_candidates if p)

    command = [
        str(rvpkg_path),
        "-force",
        "-install",
        "-add",
        str(packages_destination_folder.resolve()),
        *[str(p) for p in get_packages_from_dir(packages_source_folder)],
    ]

    subprocess.run(command, env=env).check_returncode()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()

    parser.add_argument("--rvpkg", dest="rvpkg_path", type=pathlib.Path, required=True)
    parser.add_argument("--source", dest="packages_source_folder", type=pathlib.Path, required=True)
    parser.add_argument(
        "--destination",
        dest="packages_destination_folder",
        type=pathlib.Path,
        required=True,
    )

    install_rvpkg_packages(**vars(parser.parse_args()))
