#
# Copyright (C) 2026 Makai Systems and The OpenUTV Contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#

from rv import commands as rvc
from rv import extra_commands as rve
from rv import rvtypes as rvt


class R3DSettingsMinorMode(rvt.MinorMode):
    """
    MinorMode providing interactive multi-resolution wavelet decoding
    and GPU acceleration controls for RED R3D media.
    """

    def __init__(self):
        super().__init__()

        menu = [
            (
                "Image",
                [
                    (
                        "RED (R3D) Wavelet Resolution",
                        [
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
                            ("_", None),
                            (
                                "GPU Acceleration",
                                self.toggleGPU,
                                None,
                                self.gpuState,
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
        try:
            return bool(rvc.readSettings("R3D", "gpu_acceleration", True))
        except Exception:
            return True

    def toggleGPU(self, event=None):
        try:
            new_val = not self.isGPUEnabled()
            rvc.writeSettings("R3D", "gpu_acceleration", new_val)
            self._reloadR3DSources()
            rvc.reload()
            state_str = "Enabled" if new_val else "Disabled"
            rve.displayFeedback(f"RED GPU Acceleration: {state_str}", 2.0)
        except Exception as e:
            print(f"ERROR: Failed to toggle RED GPU acceleration: {e}")

    def gpuState(self):
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
