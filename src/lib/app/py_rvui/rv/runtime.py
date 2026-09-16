#
# Copyright (C) 2023  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
import os
import sys

try:
    if "QTWEBENGINE_RESOURCES_PATH" not in os.environ or "QTWEBENGINE_LOCALES_PATH" not in os.environ:
        for p in sys.path:
            res_cand = os.path.join(p, "PySide6", "resources")
            if os.path.isdir(res_cand) and "QTWEBENGINE_RESOURCES_PATH" not in os.environ:
                os.environ["QTWEBENGINE_RESOURCES_PATH"] = res_cand
            loc_cand = os.path.join(p, "PySide6", "translations", "qtwebengine_locales")
            if os.path.isdir(loc_cand) and "QTWEBENGINE_LOCALES_PATH" not in os.environ:
                os.environ["QTWEBENGINE_LOCALES_PATH"] = loc_cand

    from PySide6.QtWebEngineCore import QWebEngineProfile

    def __dummy__():
        pass

    def setup_webview_default_profile():
        default_profile = QWebEngineProfile.defaultProfile()
        user_agent = default_profile.httpUserAgent() + " RV/" + os.environ.get("TWK_APP_VERSION", "")
        default_profile.setHttpUserAgent(user_agent)

    setup_webview_default_profile()
except Exception:
    pass
