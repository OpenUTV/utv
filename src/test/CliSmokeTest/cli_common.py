#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Shared helpers for the CLI smoke and image format round-trip tests."""

import os
import subprocess
import sys
from dataclasses import dataclass

IS_WINDOWS = sys.platform == "win32"
IS_MACOS = sys.platform == "darwin"


@dataclass
class ToolResult:
    returncode: int
    output: str
    timed_out: bool

    @property
    def crashed(self):
        if self.timed_out:
            return False
        if IS_WINDOWS:
            # NTSTATUS failures such as 0xC0000135 (DLL not found) or 0xC0000005 (access violation)
            return (self.returncode & 0xFFFFFFFF) >= 0xC0000000
        # Negative: killed by a signal. 128+N: shell-reported signal death.
        return self.returncode < 0 or self.returncode in (134, 136, 137, 139)


def prepare_environment():
    """Environment for running GUI-linked tools headless, with loader error dialogs suppressed."""
    env = os.environ.copy()
    if not IS_MACOS:
        # Tools that construct a QApplication must not need a display on CI runners.
        env.setdefault("QT_QPA_PLATFORM", "offscreen")
    env.setdefault("LC_ALL", "en_US.UTF-8")

    if IS_WINDOWS:
        import ctypes

        # SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX. Child processes inherit the
        # error mode, so a missing DLL fails with an exit code instead of a modal dialog that hangs the job.
        ctypes.windll.kernel32.SetErrorMode(0x0001 | 0x0002 | 0x8000)
    return env


def find_tool(bin_dir, name):
    """Locate a staged tool, preferring the user-facing Windows .cmd wrapper when one exists."""
    candidates = [name + ".cmd", name + ".exe", name] if IS_WINDOWS else [name]
    for candidate in candidates:
        path = os.path.join(bin_dir, candidate)
        if os.path.isfile(path):
            return path
    return None


def run_tool(cmd, env, timeout, cwd=None):
    try:
        proc = subprocess.run(
            cmd,
            env=env,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
        return ToolResult(proc.returncode, proc.stdout.decode("utf-8", errors="replace"), False)
    except subprocess.TimeoutExpired as exc:
        output = exc.output.decode("utf-8", errors="replace") if exc.output else ""
        return ToolResult(-1, output, True)
