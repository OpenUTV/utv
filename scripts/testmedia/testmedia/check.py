#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Decode generated media with utvio and report crashes, hangs and unexpected failures."""

import os
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

# Reuse the CLI smoke tests' process handling (headless environment, crash classification on every platform).
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "src", "test", "CliSmokeTest"))
from cli_common import find_tool, prepare_environment, run_tool  # noqa: E402


def default_bin_dir():
    for candidate in (
        "/Applications/UTV.app/Contents/MacOS",
        os.path.expandvars(r"%LOCALAPPDATA%\Programs\UTV\bin"),
        os.path.expandvars(r"%ProgramFiles%\UTV\bin"),
        "/opt/utv/bin",
    ):
        if os.path.isdir(candidate):
            return candidate
    return None


def check_item(utvio, env, timeout, out_root, meta):
    """Decode every frame of one item at 1/8 scale. Returns (status, detail)."""
    src = os.path.join(out_root, meta["dir"], meta["path"])
    with tempfile.TemporaryDirectory(prefix="utv-testmedia-check-") as work:
        cmd = [utvio, "-err-to-out", src, "-scale", "0.125", "-o", os.path.join(work, "out.#.jpg")]
        result = run_tool(cmd, env, timeout)
        written = len(os.listdir(work))

    if result.timed_out:
        return "HANG", f"no exit after {timeout}s"
    if result.crashed:
        return "CRASH", f"exit {result.returncode}: {last_line(result.output)}"
    if result.returncode != 0:
        status = "rejected" if meta.get("corrupt") else "FAIL"
        return status, f"exit {result.returncode}: {last_line(result.output)}"
    expected = meta.get("expect", {}).get("frames")
    if expected and not meta.get("corrupt") and written != expected:
        return "FAIL", f"decoded {written} frames, expected {expected}"
    return "ok", f"{written} frames"


def last_line(output):
    lines = [line for line in output.strip().splitlines() if line.strip()]
    for line in reversed(lines):
        if "ERROR" in line or "error" in line:
            return line.strip()[:200]
    return lines[-1].strip()[:200] if lines else ""


def run_checks(items, out_root, bin_dir, timeout, jobs):
    utvio = find_tool(bin_dir, "utvio") if bin_dir else None
    if not utvio:
        raise SystemExit(f"utvio not found in {bin_dir!r}; pass --bin-dir with the folder that contains utvio")
    env = prepare_environment()

    def one(meta):
        return meta, check_item(utvio, env, timeout, out_root, meta)

    failures = 0
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        for meta, (status, detail) in pool.map(one, items):
            bad = status in ("CRASH", "HANG", "FAIL")
            failures += bad
            print(f"{status:9} {meta['dir']:42} {detail}", flush=True)
    print(f"\n{len(items) - failures} passed, {failures} failed (utvio: {utvio})")
    return failures
