#
# Copyright (C) 2026 Makai Systems and The OpenUTV Contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#

from rv import commands as rvc
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

    def setResolution(self, res):
        try:
            rvc.writeSettings("R3D", "resolution", res)
            rvc.reload()
            rvc.displayFeedback(f"RED R3D Resolution: {res.capitalize()}", 2.0)
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
            rvc.reload()
            state_str = "Enabled" if new_val else "Disabled"
            rvc.displayFeedback(f"RED GPU Acceleration: {state_str}", 2.0)
        except Exception as e:
            print(f"ERROR: Failed to toggle RED GPU acceleration: {e}")

    def gpuState(self):
        if self.isGPUEnabled():
            return rvc.CheckedMenuState
        return rvc.UncheckedMenuState


def createMode():
    return R3DSettingsMinorMode()
