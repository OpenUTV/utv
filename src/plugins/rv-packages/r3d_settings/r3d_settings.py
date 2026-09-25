#
# Copyright (C) 2026 Makai Systems and The OpenUTV Contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#

import ctypes
import os
import sys

from rv import commands as rvc
from rv import extra_commands as rve
from rv import rvtypes as rvt


_gpu_supported_cache = None


def isGPUSupported():
    """
    Check whether hardware-accelerated RED GPU debayering is supported on this system.
    Returns True if supported, False otherwise.
    """
    global _gpu_supported_cache
    if _gpu_supported_cache is not None:
        return _gpu_supported_cache

    if sys.platform != "darwin":
        # Currently, hardware RED debayering in MovieRED is Metal-accelerated on macOS.
        # CUDA / OpenCL debayering on Windows/Linux will be detected here once enabled.
        _gpu_supported_cache = False
        return False

    # 1. Check for Metal hardware capability via Metal framework
    try:
        metal = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/Metal.framework/Metal")
        metal.MTLCreateSystemDefaultDevice.restype = ctypes.c_void_p
        dev = metal.MTLCreateSystemDefaultDevice()
        if not dev:
            _gpu_supported_cache = False
            return False
    except Exception:
        _gpu_supported_cache = False
        return False

    # 2. Check for REDMetal dynamic library in known search paths
    search_dirs = []
    if os.environ.get("RED_SDK_PATH"):
        search_dirs.append(os.environ["RED_SDK_PATH"])
    if os.environ.get("R3DSDK_DIR"):
        search_dirs.append(os.environ["R3DSDK_DIR"])

    try:
        exe_dir = os.path.dirname(os.path.abspath(sys.executable))
        search_dirs.append(exe_dir)
        search_dirs.append(os.path.join(exe_dir, "..", "PlugIns", "MovieFormats"))
        search_dirs.append(os.path.join(exe_dir, "..", "Frameworks"))
        search_dirs.append(os.path.join(exe_dir, "..", "lib"))
    except Exception:
        pass

    home = os.path.expanduser("~")
    search_dirs.append(os.path.join(home, "Library", "Application Support", "OpenUTV", "RED"))
    search_dirs.append(os.path.join(home, "Library", "Application Support", "RED"))
    search_dirs.append(os.path.join(home, ".local", "share", "openutv", "red"))

    search_dirs.extend(
        [
            "/Applications/REDCINE-X Professional/RED PLAYER.app/Contents/MacOS",
            "/Applications/REDCINE-X Professional/REDCINE-X PRO.app/Contents/MacOS",
            "/Applications/RED PLAYER.app/Contents/MacOS",
            "/Applications/REDCINE-X PRO/REDCINE-X PRO.app/Contents/MacOS",
            "/Applications/REDCINE-X PRO/REDCINE-X PRO.app/Contents/Frameworks",
            "/Library/Application Support/RED",
            "/usr/local/lib",
            "/opt/homebrew/lib",
        ]
    )

    for d in search_dirs:
        dylib_path = os.path.join(d, "REDMetal.dylib")
        if os.path.isfile(dylib_path):
            _gpu_supported_cache = True
            return True

    _gpu_supported_cache = False
    return False


class R3DSettingsMinorMode(rvt.MinorMode):
    """
    MinorMode providing interactive multi-resolution wavelet decoding
    and GPU acceleration controls for RED R3D media under Image > RED.
    """

    def __init__(self):
        super().__init__()

        # Out-of-the-box automatic GPU acceleration configuration:
        # If the host system supports RED GPU debayering and the setting has not
        # yet been configured, enable it by default for the best playback performance.
        if isGPUSupported():
            try:
                configured = bool(rvc.readSettings("R3D", "gpu_acceleration_configured", False))
                if not configured:
                    rvc.writeSettings("R3D", "gpu_acceleration", True)
                    rvc.writeSettings("R3D", "gpu_acceleration_configured", True)
            except Exception:
                pass

        menu = [
            (
                "Image",
                [
                    (
                        "RED",
                        [
                            (
                                "GPU Acceleration",
                                self.toggleGPU,
                                None,
                                self.gpuState,
                            ),
                            ("_", None),
                            (
                                "Full Resolution (1:1)",
                                lambda e: self.setResolution("full"),
                                None,
                                lambda: self.resolutionState("full"),
                            ),
                            (
                                "Half Resolution (1:2 - Fast)",
                                lambda e: self.setResolution("half"),
                                None,
                                lambda: self.resolutionState("half"),
                            ),
                            (
                                "Quarter Resolution (1:4 - Realtime)",
                                lambda e: self.setResolution("quarter"),
                                None,
                                lambda: self.resolutionState("quarter"),
                            ),
                            (
                                "Eighth Resolution (1:8 - Proxy)",
                                lambda e: self.setResolution("eighth"),
                                None,
                                lambda: self.resolutionState("eighth"),
                            ),
                        ],
                    )
                ],
            )
        ]

        self.init("r3d_settings", None, None, menu)

    def currentResolution(self):
        try:
            return rvc.readSettings("R3D", "resolution", "half")
        except Exception:
            return "half"

    def _reloadR3DSources(self):
        """Reload any active FileSource nodes displaying R3D media so new decode settings take effect."""
        for src in rvc.nodesOfType("RVFileSource"):
            try:
                movies = rvc.getStringProperty(f"{src}.media.movie")
                if any(m.lower().endswith(".r3d") for m in movies):
                    rvc.setStringProperty(f"{src}.media.movie", movies, True)
            except Exception:
                pass

    def setResolution(self, res):
        try:
            rvc.writeSettings("R3D", "resolution", res)
            self._reloadR3DSources()
            rvc.reload()
            rve.displayFeedback(f"RED R3D Resolution: {res.capitalize()}", 2.0)
        except Exception as e:
            print(f"ERROR: Failed to set R3D resolution: {e}")

    def resolutionState(self, res):
        cur = self.currentResolution()
        if cur == res:
            return rvc.CheckedMenuState
        return rvc.UncheckedMenuState

    def isGPUEnabled(self):
        if not isGPUSupported():
            return False
        try:
            return bool(rvc.readSettings("R3D", "gpu_acceleration", True))
        except Exception:
            return True

    def toggleGPU(self, event=None):
        if not isGPUSupported():
            rve.displayFeedback("RED GPU Acceleration: Not supported on this system", 3.0)
            return
        try:
            new_val = not self.isGPUEnabled()
            rvc.writeSettings("R3D", "gpu_acceleration", new_val)
            rvc.writeSettings("R3D", "gpu_acceleration_configured", True)
            self._reloadR3DSources()
            rvc.reload()
            state_str = "Enabled" if new_val else "Disabled"
            rve.displayFeedback(f"RED GPU Acceleration: {state_str}", 2.0)
        except Exception as e:
            print(f"ERROR: Failed to toggle RED GPU acceleration: {e}")

    def gpuState(self):
        if not isGPUSupported():
            return rvc.DisabledMenuState
        if self.isGPUEnabled():
            return rvc.CheckedMenuState
        return rvc.UncheckedMenuState


_theMode = None


def theMode():
    global _theMode
    return _theMode


def createMode():
    global _theMode
    _theMode = R3DSettingsMinorMode()
    return _theMode
