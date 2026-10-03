#!/usr/bin/env python3
#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Test the Windows launchers in an installed tree (cmake --install, or an extracted release zip).

Runs the tools from <install>\\cmd the way users and scripts do, with OpenUTVDeps neither on PATH nor
named by an environment variable: the launchers must find it themselves. Checks that

  * every launcher in cmd starts its program, including the legacy rv* names,
  * output and exit codes come back to the caller,
  * a tool started with CREATE_NO_WINDOW (as the viewer and scripts start helpers) runs without a
    visible console window,
  * killing a launcher also ends the program it started.

Usage: launcher_test.py --install-dir <dir> [--timeout 60]
"""

import argparse
import os
import re
import subprocess
import sys
import time

from cli_common import prepare_environment, run_tool

# (launcher, args, expected exit code, regex that must appear in stdout+stderr)
CHECKS = [
    ("utvio", ["-version"], 0, r"^\d{4}\.\d+"),
    ("rvio", ["-version"], 0, r"^\d{4}\.\d+"),
    ("utvls", ["-version"], 0, r"^\d{4}\.\d+"),
    ("rvls", ["-version"], 0, r"^\d{4}\.\d+"),
    ("utvpkg", ["-list"], 0, r"\.rvpkg"),
    ("rvpkg", ["-list"], 0, r"\.rvpkg"),
    ("rvpush", ["-help"], None, r"usage: rvpush"),
    ("rvshell", ["-help"], None, r"usage: rvshell"),
    ("rvprof", ["-help"], None, r"usage: rvprof"),
    ("py-interp", ["-c", "import sys, ssl, sqlite3; print('py-interp-ok'); sys.exit(7)"], 7, r"py-interp-ok"),
    ("openutv-diagnostics.cmd", ["--help"], 0, r"Usage: openutv-diagnostics"),
]

CONSOLE_PROBE = (
    "import ctypes; h = ctypes.windll.kernel32.GetConsoleWindow(); "
    "print('visible-console' if h and ctypes.windll.user32.IsWindowVisible(h) else 'no-visible-console')"
)


def isolated_environment():
    """The caller's environment without OpenUTVDeps on PATH or in variables."""
    env = prepare_environment()
    for name in (
        "UTV_DEPS_ROOT",
        "OPENUTV_DEPS_ROOT",
        "PYTHONHOME",
        "QT_PLUGIN_PATH",
        "QT_QPA_PLATFORM_PLUGIN_PATH",
        "UTV_OPENGL",
    ):
        env.pop(name, None)
    keep = [p for p in env.get("PATH", "").split(os.pathsep) if p and "openutvdeps" not in p.lower()]
    env["PATH"] = os.pathsep.join(keep)
    return env


def program_count(image):
    out = subprocess.run(
        ["tasklist", "/FI", f"IMAGENAME eq {image}", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        creationflags=subprocess.CREATE_NO_WINDOW,
        check=False,
    ).stdout
    return out.lower().count(image.lower())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--install-dir", required=True, help="Installed OpenUTV directory (has bin and cmd)")
    parser.add_argument("--timeout", type=int, default=60, help="Per-command timeout in seconds")
    args = parser.parse_args()

    if sys.platform != "win32":
        print("Windows only")
        return 0

    cmd_dir = os.path.join(args.install_dir, "cmd")
    bin_dir = os.path.join(args.install_dir, "bin")
    env = isolated_environment()
    failures = []

    def fail(label, problem, output=""):
        failures.append(f"{label}: {problem}")
        print(f"FAIL {label}: {problem}")
        for line in output.splitlines()[-20:]:
            print(f"  {line}")

    for directory in (bin_dir, cmd_dir):
        for required in ("utv.exe", "rv.exe", "utvio.exe"):
            if not os.path.isfile(os.path.join(directory, required)):
                fail(required, f"missing in {directory}")
    for program in ("utv-bin.exe", "utvio-bin.exe", "opengl32.dll"):
        if not os.path.isfile(os.path.join(bin_dir, program)):
            fail(program, f"missing in {bin_dir}")
    for stale in ("rv-bin.exe", "utv-cli-launcher.exe", "opengl32sw.dll", "utvio.cmd", "py-interp.cmd", "UTV.bat"):
        if os.path.exists(os.path.join(bin_dir, stale)):
            fail(stale, f"should not be installed in {bin_dir}")

    for tool, tool_args, expected, pattern in CHECKS:
        path = os.path.join(cmd_dir, tool if tool.endswith(".cmd") else tool + ".exe")
        label = f"cmd\\{os.path.basename(path)} {' '.join(tool_args)}"
        result = run_tool([path] + tool_args, env, args.timeout)
        if result.timed_out:
            fail(label, f"timed out after {args.timeout}s", result.output)
        elif expected is not None and result.returncode != expected:
            fail(label, f"exit code {result.returncode}, expected {expected}", result.output)
        elif not re.search(pattern, result.output, re.MULTILINE):
            fail(label, f"output did not match /{pattern}/", result.output)
        else:
            print(f"ok   {label}")

    # Started without a console window, the launcher and the program it starts must not create one.
    # (A GUI-subsystem launcher in front of a console program did: the console flashes in #58.)
    probe = subprocess.run(
        [os.path.join(cmd_dir, "py-interp.exe"), "-c", CONSOLE_PROBE],
        env=env,
        capture_output=True,
        text=True,
        timeout=args.timeout,
        creationflags=subprocess.CREATE_NO_WINDOW,
        check=False,
    )
    if "no-visible-console" in probe.stdout:
        print("ok   CREATE_NO_WINDOW: no console window")
    else:
        fail("CREATE_NO_WINDOW", f"tool got a visible console (exit {probe.returncode})", probe.stdout + probe.stderr)

    # Killing the launcher ends the program too (script timeouts, Task Manager).
    before = program_count("py-interp-bin.exe")
    proc = subprocess.Popen(
        [os.path.join(cmd_dir, "py-interp.exe"), "-c", "import time; time.sleep(120)"],
        env=env,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )
    time.sleep(5)
    started = program_count("py-interp-bin.exe") - before
    proc.kill()
    proc.wait()
    time.sleep(3)
    left = program_count("py-interp-bin.exe") - before
    if started == 1 and left == 0:
        print("ok   killing the launcher ends the program")
    else:
        fail("kill", f"{started} program(s) started, {left} left running after the launcher was killed")

    if failures:
        print(f"\n{len(failures)} launcher checks failed")
        return 1
    print("\nAll launcher checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
