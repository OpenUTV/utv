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
    Supports Apple Metal on macOS and OpenCL on Windows, Linux, and macOS.
    Returns True if supported, False otherwise.
    """
    global _gpu_supported_cache
    if _gpu_supported_cache is not None:
        return _gpu_supported_cache

    # 1. Check for hardware GPU framework/driver capability
    has_gpu_runtime = False
    if sys.platform == "darwin":
        try:
            metal = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/Metal.framework/Metal")
            metal.MTLCreateSystemDefaultDevice.restype = ctypes.c_void_p
            dev = metal.MTLCreateSystemDefaultDevice()
            if dev:
                has_gpu_runtime = True
        except Exception:
            pass

    if not has_gpu_runtime:
        # Check OpenCL across Windows, Linux, and macOS
        opencl_names = []
        if sys.platform == "win32":
            opencl_names = ["OpenCL.dll"]
        elif sys.platform == "darwin":
            opencl_names = ["/System/Library/Frameworks/OpenCL.framework/OpenCL"]
        else:
            opencl_names = ["libOpenCL.so.1", "libOpenCL.so"]

        for name in opencl_names:
            try:
                ctypes.cdll.LoadLibrary(name)
                has_gpu_runtime = True
                break
            except Exception:
                pass

    if not has_gpu_runtime:
        _gpu_supported_cache = False
        return False

    # 2. Check for matching RED dynamic GPU library in known search paths
    # macOS: REDMetal.dylib or REDOpenCL.dylib
    # Windows: REDOpenCL-x64.dll or REDCuda-x64.dll
    # Linux: REDOpenCL-x64.so or REDCuda-x64.so
    target_gpu_libs = []
    if sys.platform == "darwin":
        target_gpu_libs = ["REDMetal.dylib", "REDOpenCL.dylib"]
    elif sys.platform == "win32":
        target_gpu_libs = ["REDOpenCL-x64.dll", "REDCuda-x64.dll"]
    else:
        target_gpu_libs = ["REDOpenCL-x64.so", "REDCuda-x64.so"]

    search_dirs = []
    if os.environ.get("RED_SDK_PATH"):
        search_dirs.append(os.environ["RED_SDK_PATH"])
    if os.environ.get("R3DSDK_DIR"):
        search_dirs.append(os.environ["R3DSDK_DIR"])

    try:
        exe_dir = os.path.dirname(os.path.abspath(sys.executable))
        search_dirs.append(exe_dir)
        search_dirs.append(os.path.join(exe_dir, "..", "PlugIns", "MovieFormats"))
        search_dirs.append(os.path.join(exe_dir, "PlugIns", "MovieFormats"))
        search_dirs.append(os.path.join(exe_dir, "..", "Frameworks"))
        search_dirs.append(os.path.join(exe_dir, "..", "lib"))
    except Exception:
        pass

    home = os.path.expanduser("~")
    search_dirs.append(os.path.join(home, "Library", "Application Support", "OpenUTV", "RED"))
    search_dirs.append(os.path.join(home, "Library", "Application Support", "RED"))
    search_dirs.append(os.path.join(home, ".local", "share", "openutv", "red"))
    if os.environ.get("APPDATA"):
        search_dirs.append(os.path.join(os.environ["APPDATA"], "OpenUTV", "RED"))

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
            "C:/Program Files/RED/RED PLAYER",
            "C:/Program Files/RED DIGITAL CINEMA/REDCINE-X PRO",
            "C:/Program Files/RED DIGITAL CINEMA/RED PLAYER",
            "C:/Program Files/RED/REDCINE-X PRO",
            "C:/Program Files/RED Digital Cinema",
            "/usr/local/lib",
            "/opt/red",
        ]
    )

    for d in search_dirs:
        for lib in target_gpu_libs:
            dylib_path = os.path.join(d, lib)
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
