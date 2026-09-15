#
# Copyright (C) 2026 Makai Systems. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

import csv
import io
import json
import os

from rv import commands, qtutils, rvtypes

try:
    from PySide6 import QtGui
    from PySide6.QtCore import Qt, QTimer
    from PySide6.QtWidgets import (
        QApplication,
        QComboBox,
        QDialog,
        QHBoxLayout,
        QHeaderView,
        QLabel,
        QLineEdit,
        QMenu,
        QPushButton,
        QTabWidget,
        QTreeWidget,
        QTreeWidgetItem,
        QVBoxLayout,
    )
except ImportError:
    try:
        from PySide2 import QtGui
        from PySide2.QtCore import Qt, QTimer
        from PySide2.QtWidgets import (
            QApplication,
            QComboBox,
            QDialog,
            QHBoxLayout,
            QHeaderView,
            QLabel,
            QLineEdit,
            QMenu,
            QPushButton,
            QTabWidget,
            QTreeWidget,
            QTreeWidgetItem,
            QVBoxLayout,
        )
    except ImportError:
        pass


class MediaInfoDialog(QDialog):
    """
    Native Qt Media Information Dialog with selectable text, search filtering,
    and one-click clipboard copying.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Media Information - OpenUTV")
        self.resize(750, 560)

        # Style dialog to blend natively with OpenUTV dark UI
        self.setStyleSheet("""
            QDialog {
                background-color: #2b2b2b;
                color: #e0e0e0;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            }
            QLabel {
                color: #e0e0e0;
            }
            QLineEdit {
                background-color: #1e1e1e;
                color: #ffffff;
                border: 1px solid #444444;
                border-radius: 4px;
                padding: 6px 10px;
                font-size: 13px;
            }
            QLineEdit:focus {
                border: 1px solid #007acc;
            }
            QTabWidget::pane {
                border: 1px solid #3c3c3c;
                background-color: #222222;
                border-radius: 4px;
            }
            QTabBar::tab {
                background-color: #2b2b2b;
                color: #aaaaaa;
                padding: 8px 16px;
                margin-right: 2px;
                border-top-left-radius: 4px;
                border-top-right-radius: 4px;
            }
            QTabBar::tab:selected {
                background-color: #222222;
                color: #ffffff;
                font-weight: bold;
            }
            QTreeWidget {
                background-color: #222222;
                color: #dcdcdc;
                border: none;
                font-size: 13px;
                alternate-background-color: #282828;
            }
            QTreeWidget::item {
                padding: 3px 0px;
            }
            QTreeWidget::item:selected {
                background-color: #094771;
                color: #ffffff;
            }
            QHeaderView::section {
                background-color: #1e1e1e;
                color: #aaaaaa;
                padding: 6px 8px;
                border: none;
                border-right: 1px solid #333333;
                font-weight: bold;
                font-size: 12px;
            }
            QPushButton {
                background-color: #383838;
                color: #ffffff;
                border: 1px solid #555555;
                border-radius: 4px;
                padding: 6px 14px;
                font-size: 13px;
            }
            QPushButton:hover {
                background-color: #484848;
                border-color: #007acc;
            }
            QPushButton:pressed {
                background-color: #007acc;
            }
            QPushButton#copyBtn {
                background-color: #0e639c;
                border-color: #1177bb;
                font-weight: bold;
            }
            QPushButton#copyBtn:hover {
                background-color: #1177bb;
            }
            QComboBox {
                background-color: #2b2b2b;
                color: #e0e0e0;
                border: 1px solid #555555;
                border-radius: 4px;
                padding: 5px 10px;
                font-size: 13px;
            }
            QComboBox:hover {
                border-color: #007acc;
            }
            QComboBox::drop-down {
                subcontrol-origin: padding;
                subcontrol-position: top right;
                width: 20px;
                border-left: none;
            }
            QComboBox QAbstractItemView {
                background-color: #252525;
                color: #e0e0e0;
                selection-background-color: #094771;
                selection-color: #ffffff;
                border: 1px solid #444444;
            }
        """)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 14, 14, 14)
        layout.setSpacing(10)

        # Media / Source selection row
        sourceRow = QHBoxLayout()
        sourceLabel = QLabel("<b>Media:</b>")
        sourceLabel.setStyleSheet("color: #4da6ff; font-weight: bold;")
        self.sourceCombo = QComboBox()
        self.sourceCombo.setMinimumWidth(320)
        self.sourceCombo.currentIndexChanged.connect(self.onSourceComboChanged)
        sourceRow.addWidget(sourceLabel)
        sourceRow.addWidget(self.sourceCombo)

        self.refreshBtn = QPushButton("↻ Refresh")
        self.refreshBtn.setToolTip("Refresh metadata from active viewport or selected media")
        self.refreshBtn.clicked.connect(lambda: self.refresh(rebuildCombo=True))
        sourceRow.addWidget(self.refreshBtn)
        sourceRow.addStretch()
        layout.addLayout(sourceRow)

        # File header info
        self.fileLabel = QLabel("<b>File:</b> None loaded")
        self.fileLabel.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.fileLabel.setWordWrap(True)
        layout.addWidget(self.fileLabel)

        # Filter bar
        filterLayout = QHBoxLayout()
        filterLabel = QLabel("Filter:")
        self.filterEdit = QLineEdit()
        self.filterEdit.setPlaceholderText("Type to filter metadata keys or values...")
        self.filterEdit.textChanged.connect(self.filterAttributes)
        filterLayout.addWidget(filterLabel)
        filterLayout.addWidget(self.filterEdit)
        layout.addLayout(filterLayout)

        # Tab Widget
        self.tabs = QTabWidget()
        layout.addWidget(self.tabs)

        # Tab 1: Overview Tree
        self.overviewTree = QTreeWidget()
        self.overviewTree.setHeaderLabels(["Property", "Value"])
        self.overviewTree.header().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.overviewTree.header().setSectionResizeMode(1, QHeaderView.Stretch)
        self.overviewTree.setAlternatingRowColors(True)
        self.overviewTree.setRootIsDecorated(True)
        self.overviewTree.setContextMenuPolicy(Qt.CustomContextMenu)
        self.overviewTree.customContextMenuRequested.connect(self.showTreeContextMenu)
        self.tabs.addTab(self.overviewTree, "Overview")

        # Tab 2: All Attributes Tree
        self.allAttrsTree = QTreeWidget()
        self.allAttrsTree.setHeaderLabels(["Attribute", "Value"])
        self.allAttrsTree.header().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.allAttrsTree.header().setSectionResizeMode(1, QHeaderView.Stretch)
        self.allAttrsTree.setAlternatingRowColors(True)
        self.allAttrsTree.setRootIsDecorated(False)
        self.allAttrsTree.setContextMenuPolicy(Qt.CustomContextMenu)
        self.allAttrsTree.customContextMenuRequested.connect(self.showTreeContextMenu)
        self.tabs.addTab(self.allAttrsTree, "All Attributes")

        # Bottom row: status, Copy Overview, Format Selector, Copy All, Close
        btnLayout = QHBoxLayout()
        self.statusLabel = QLabel("")
        self.statusLabel.setStyleSheet("color: #4ec9b0; font-weight: bold;")
        btnLayout.addWidget(self.statusLabel)
        btnLayout.addStretch()

        self.copyOverviewBtn = QPushButton("Copy Overview")
        self.copyOverviewBtn.clicked.connect(self.copyOverview)
        btnLayout.addWidget(self.copyOverviewBtn)

        fmtLabel = QLabel("Format:")
        fmtLabel.setStyleSheet("color: #aaaaaa; margin-left: 8px;")
        btnLayout.addWidget(fmtLabel)

        self.formatCombo = QComboBox()
        self.formatCombo.addItems(["JSON", "Plain Text", "CSV", "Markdown", "YAML"])
        self.formatCombo.currentTextChanged.connect(self.onFormatChanged)
        btnLayout.addWidget(self.formatCombo)

        self.copyAllBtn = QPushButton("Copy All (JSON)")
        self.copyAllBtn.setObjectName("copyBtn")
        self.copyAllBtn.clicked.connect(self.copyAllMetadata)
        btnLayout.addWidget(self.copyAllBtn)

        self.closeBtn = QPushButton("Close")
        self.closeBtn.clicked.connect(self.close)
        btnLayout.addWidget(self.closeBtn)

        layout.addLayout(btnLayout)

        self.currentAttrs = []
        self.currentSource = None

    def showStatus(self, text):
        self.statusLabel.setText(text)
        QTimer.singleShot(3000, lambda: self.statusLabel.setText(""))

    def updateSourceCombo(self):
        self.sourceCombo.blockSignals(True)
        currData = self.sourceCombo.currentData()
        self.sourceCombo.clear()
        self.sourceCombo.addItem("✦ Auto (Active Viewport / Playhead)", "__auto__")

        try:
            groups = commands.nodesOfType("RVSourceGroup") or []
        except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
            groups = []

        for grp in groups:
            filePath = self.getSourceFilePath(grp)
            base = os.path.basename(filePath) if filePath else grp
            label = f"{grp} ({base})"
            self.sourceCombo.addItem(label, grp)

        # Restore previous selection if still present
        restoreIdx = 0
        if currData:
            for i in range(self.sourceCombo.count()):
                if self.sourceCombo.itemData(i) == currData:
                    restoreIdx = i
                    break
        self.sourceCombo.setCurrentIndex(restoreIdx)
        self.sourceCombo.blockSignals(False)

    def onSourceComboChanged(self, index):
        self.refresh(rebuildCombo=False)

    def onFrameChanged(self):
        # In Auto mode, update if the active source rendered at the playhead changes
        if self.sourceCombo.currentData() == "__auto__":
            active = self.getActiveViewportSource()
            if active != self.currentSource:
                self.refresh(rebuildCombo=False)

    def getSourceNode(self, groupNode):
        if not groupNode:
            return None
        for t in ("RVFileSource", "RVImageSource"):
            try:
                members = commands.nodesInGroupOfType(groupNode, t)
                if members:
                    return members[0]
            except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
                pass
        return groupNode

    def getSourceFilePath(self, node):
        if not node:
            return ""
        target = self.getSourceNode(node)
        # Try getStringProperty
        try:
            prop = commands.getStringProperty(target + ".media.movie")
            if prop and prop[0]:
                return prop[0]
        except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
            pass
        # Try sourceMedia
        try:
            med = commands.sourceMedia(target)
            if med and isinstance(med, (list, tuple)) and med[0]:
                return med[0]
            elif isinstance(med, str) and med:
                return med
        except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
            pass
        return ""

    def getActiveViewportSource(self):
        # 1. First try sourcesAtFrame at current playhead frame
        try:
            fr = commands.frame()
            active = commands.sourcesAtFrame(fr)
            if active:
                try:
                    grp = commands.nodeGroup(active[0])
                    if grp:
                        return grp
                except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
                    pass
                return active[0]
        except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
            pass

        # 2. Try sourcesRendered
        try:
            rendered = commands.sourcesRendered()
            if rendered:
                r = rendered[0]
                node_name = getattr(r, "node", None) or getattr(r, "name", None) or (r if isinstance(r, str) else None)
                if node_name:
                    try:
                        grp = commands.nodeGroup(node_name)
                        if grp:
                            return grp
                    except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
                        pass
                    return node_name
        except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
            pass

        # 3. Fallback to first source group in session
        try:
            groups = commands.nodesOfType("RVSourceGroup")
            if groups:
                return groups[0]
        except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
            pass

        return None

    def getAttributesForSource(self, source):
        if not source:
            return []

        leaf = self.getSourceNode(source)
        filePath = self.getSourceFilePath(source)

        strategies = [
            lambda: commands.sourceAttributes(source),
            lambda: commands.sourceAttributes(leaf) if (leaf and leaf != source) else None,
            lambda: commands.sourceAttributes(source, filePath) if filePath else None,
            lambda: commands.sourceAttributes(leaf, filePath) if (leaf and leaf != source and filePath) else None,
            lambda: commands.sourceAttributes(),
        ]

        for strat in strategies:
            try:
                attrs = strat()
                if attrs:
                    return attrs
            except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
                continue

        return []

    def refresh(self, rebuildCombo=True):
        if rebuildCombo:
            self.updateSourceCombo()

        selected = self.sourceCombo.currentData()
        if selected == "__auto__" or not selected:
            source = self.getActiveViewportSource()
        else:
            source = selected

        if not source:
            self.fileLabel.setText("<b>File:</b> No media currently active in session")
            self.overviewTree.clear()
            self.allAttrsTree.clear()
            self.currentAttrs = []
            self.currentSource = None
            return

        self.currentSource = source
        attrs = self.getAttributesForSource(source)
        self.currentAttrs = attrs or []
        attrDict = dict(self.currentAttrs)

        # Update file header
        filepath = attrDict.get("File", attrDict.get("Sequence", self.getSourceFilePath(source) or source))
        self.fileLabel.setText(f"<b>File:</b> {filepath}")

        # Update Overview Tab
        self.overviewTree.clear()

        def addCategory(name, items):
            cat = QTreeWidgetItem(self.overviewTree, [name, ""])
            cat.setExpanded(True)
            font = cat.font(0)
            font.setBold(True)
            cat.setFont(0, font)
            cat.setForeground(0, QtGui.QColor("#4da6ff"))
            hasItems = False
            for k, v in items:
                if v:
                    QTreeWidgetItem(cat, [str(k), str(v)])
                    hasItems = True
            if not hasItems:
                cat.setHidden(True)
            return cat

        # File & Container Info
        containerItems = [
            ("Container", attrDict.get("Container", "")),
            ("Duration", attrDict.get("Duration", "")),
            ("FPS", attrDict.get("FPS", "")),
            ("Bit Rate", attrDict.get("BitRate", "")),
            ("Resolution", attrDict.get("Resolution", attrDict.get("DisplayResolution", ""))),
            ("Channels", attrDict.get("Channels", "")),
        ]
        addCategory("Container & General", containerItems)

        # Video Info
        videoItems = [
            ("Codec", attrDict.get("Codec", attrDict.get("VideoCodec", ""))),
            ("Codec ID / Name", attrDict.get("CodecName", "")),
            ("Pixel Format", attrDict.get("PixelFormat", attrDict.get("VideoPixelFormat", ""))),
            ("Pixel Aspect Ratio", attrDict.get("PixelAspectRatio", "")),
            ("Video Tracks", attrDict.get("VideoTracks", "")),
            ("Rotation", attrDict.get("Rotation", "")),
        ]
        addCategory("Video Stream", videoItems)

        # Color & Mastering Info
        colorItems = [
            ("Color Space", attrDict.get("ColorSpace", attrDict.get("NSImage/ColorSpaceName", ""))),
            ("Color Primaries", attrDict.get("ColorPrimaries", attrDict.get("Codec/Primaries", ""))),
            ("Color Transfer", attrDict.get("ColorTransfer", attrDict.get("Codec/Transfer", ""))),
            ("Color Range", attrDict.get("ColorRange", attrDict.get("ColorSpace/Range", ""))),
            ("Matrix", attrDict.get("Codec/Matrix", "")),
            ("Chroma Placement", attrDict.get("ColorSpace/ChromaPlacement", "")),
        ]
        addCategory("Color & Mastering", colorItems)

        # Camera & Optics (EXIF)
        cameraItems = [
            ("Make / Camera Brand", attrDict.get("Exif:Make", attrDict.get("Make", ""))),
            ("Model / Camera Body", attrDict.get("Exif:Model", attrDict.get("Model", ""))),
            ("Lens", attrDict.get("Exif:LensModel", attrDict.get("LensModel", attrDict.get("Exif:LensMake", "")))),
            ("Focal Length", attrDict.get("Exif:FocalLength", attrDict.get("FocalLength", ""))),
            (
                "Focal Length (35mm Eq)",
                attrDict.get("Exif:FocalLengthIn35mmFilm", attrDict.get("FocalLengthIn35mmFormat", "")),
            ),
            (
                "Aperture / F-Stop",
                attrDict.get("Exif:FNumber", attrDict.get("FNumber", attrDict.get("ApertureValue", ""))),
            ),
            (
                "Shutter Speed / Exposure",
                attrDict.get("Exif:ExposureTime", attrDict.get("ExposureTime", attrDict.get("ShutterSpeedValue", ""))),
            ),
            (
                "ISO Sensitivity",
                attrDict.get(
                    "Exif:PhotographicSensitivity", attrDict.get("Exif:ISOSpeedRatings", attrDict.get("ISO", ""))
                ),
            ),
            ("Exposure Bias", attrDict.get("Exif:ExposureBiasValue", "")),
            ("White Balance", attrDict.get("Exif:WhiteBalance", "")),
            ("Metering Mode", attrDict.get("Exif:MeteringMode", "")),
            ("Flash", attrDict.get("Exif:Flash", "")),
            ("Date / Time Captured", attrDict.get("Exif:DateTimeOriginal", attrDict.get("DateTime", ""))),
            ("GPS Coordinates", attrDict.get("GPS:Position", attrDict.get("GPS:Latitude", ""))),
            ("Software / Firmware", attrDict.get("Software", attrDict.get("Exif:Software", ""))),
        ]
        addCategory("Camera & Optics (EXIF)", cameraItems)

        # Audio Info
        audioItems = [
            ("Audio Codec", attrDict.get("AudioCodec", "")),
            ("Audio Channels", attrDict.get("AudioChannels", "")),
            ("Sample Rate", attrDict.get("AudioSamplingRate", "")),
            ("Sample Format", attrDict.get("AudioSampleFormat", "")),
            ("Bits Per Sample", attrDict.get("AudioBitsPerSample", "")),
            ("Audio Language", attrDict.get("AudioLanguage", "")),
        ]
        addCategory("Audio Stream", audioItems)

        # Update All Attributes Tab
        self.populateAllAttributes()

    def populateAllAttributes(self):
        self.allAttrsTree.clear()
        query = self.filterEdit.text().strip().lower()
        for key, val in self.currentAttrs:
            if not key and not val:
                continue
            k_str = str(key)
            v_str = str(val)
            if query and (query not in k_str.lower() and query not in v_str.lower()):
                continue
            QTreeWidgetItem(self.allAttrsTree, [k_str, v_str])

    def filterAttributes(self, text):
        self.populateAllAttributes()

    def copyOverview(self):
        lines = []
        source = self.currentSource or "Unknown"
        lines.append(f"--- Media Overview: {source} ---")
        filepath = dict(self.currentAttrs).get("File", source)
        lines.append(f"File: {filepath}\n")

        for i in range(self.overviewTree.topLevelItemCount()):
            cat = self.overviewTree.topLevelItem(i)
            if cat.isHidden():
                continue
            lines.append(f"[{cat.text(0)}]")
            for j in range(cat.childCount()):
                child = cat.child(j)
                lines.append(f"  {child.text(0)}: {child.text(1)}")
            lines.append("")

        text = "\n".join(lines)
        QApplication.clipboard().setText(text)
        self.showStatus("✓ Overview copied to clipboard!")

    def onFormatChanged(self, fmt_name):
        self.copyAllBtn.setText(f"Copy All ({fmt_name})")

    def showTreeContextMenu(self, pos):
        sender = self.sender()
        if not sender:
            return
        item = sender.itemAt(pos)
        if not item:
            return
        key = item.text(0)
        val = item.text(1)
        menu = QMenu(self)
        if val:
            copyValAction = menu.addAction(f"Copy Value: {val[:30]}...")
            copyValAction.triggered.connect(lambda: QApplication.clipboard().setText(val))
        copyKeyAction = menu.addAction(f"Copy Key: {key[:30]}")
        copyKeyAction.triggered.connect(lambda: QApplication.clipboard().setText(key))
        if val:
            copyBothAction = menu.addAction("Copy Key and Value")
            copyBothAction.triggered.connect(lambda: QApplication.clipboard().setText(f"{key}: {val}"))

        execFunc = getattr(menu, "exec", getattr(menu, "exec_", None))
        if execFunc:
            execFunc(sender.viewport().mapToGlobal(pos))

    def copyAllMetadata(self):
        if not self.currentAttrs:
            self.showStatus("No metadata available to copy")
            return

        fmt = self.formatCombo.currentText() if hasattr(self, "formatCombo") else "JSON"
        source = self.currentSource or "Unknown"

        if fmt == "JSON":
            data = {}
            for k, v in self.currentAttrs:
                if not k:
                    continue
                val = v
                if isinstance(val, str):
                    if val.isdigit():
                        val = int(val)
                    else:
                        try:
                            val = float(val)
                        except ValueError:
                            pass
                if k in data:
                    if isinstance(data[k], list):
                        data[k].append(val)
                    else:
                        data[k] = [data[k], val]
                else:
                    data[k] = val
            text = json.dumps(data, indent=2, ensure_ascii=False)
            statusMsg = "✓ Metadata copied as JSON!"

        elif fmt == "CSV":
            out = io.StringIO()
            writer = csv.writer(out, quoting=csv.QUOTE_MINIMAL)
            writer.writerow(["Attribute", "Value"])
            for k, v in self.currentAttrs:
                writer.writerow([k, v])
            text = out.getvalue()
            statusMsg = "✓ Metadata copied as CSV!"

        elif fmt == "Markdown":
            lines = [f"### Media Metadata: `{source}`\n", "| Attribute | Value |", "| :--- | :--- |"]
            for k, v in self.currentAttrs:
                if k or v:
                    safe_k = str(k).replace("|", "\\|").replace("\n", " ")
                    safe_v = str(v).replace("|", "\\|").replace("\n", " ")
                    lines.append(f"| {safe_k} | {safe_v} |")
            text = "\n".join(lines)
            statusMsg = "✓ Metadata copied as Markdown!"

        elif fmt == "YAML":
            lines = [f"# Media Metadata: {source}"]
            for k, v in self.currentAttrs:
                if k:
                    val_str = str(v)
                    if any(c in val_str for c in ":#{}[]|>&*!%@`,\n") or val_str.strip() != val_str:
                        lines.append(f'"{k}": {json.dumps(val_str)}')
                    else:
                        lines.append(f'"{k}": {val_str}')
            text = "\n".join(lines)
            statusMsg = "✓ Metadata copied as YAML!"

        else:  # Plain Text
            lines = [f"--- All Metadata: {source} ---"]
            for k, v in self.currentAttrs:
                if k or v:
                    lines.append(f"{k}: {v}")
            text = "\n".join(lines)
            statusMsg = "✓ Metadata copied as Text!"

        QApplication.clipboard().setText(text)
        self.showStatus(statusMsg)


class MediaInfoMinorMode(rvtypes.MinorMode):
    """
    OpenUTV Media Information MinorMode
    """

    def __init__(self):
        super().__init__()
        globalBindings = [
            ("key-down--control--i", self.showDialog, "Show Media Information"),
            ("show-media-info-dialog", self.showDialog, "Show Media Information"),
            ("frame-changed", self.onFrameChanged, "Update Media Info on Frame Change"),
            ("new-source", self.onSourceChanged, "Update Media Info on New Source"),
            ("source-modified", self.onSourceChanged, "Update Media Info on Source Modified"),
            ("source-media-changed", self.onSourceChanged, "Update Media Info on Media Changed"),
            ("after-graph-view-change", self.onSourceChanged, "Update Media Info on View Change"),
        ]
        # Define menu under Window > Media Information...
        menu = [("Window", [("_", None), ("Media Information...", self.showDialog, "key-down--control--i", None)])]
        self.init("media_info", globalBindings, None, menu)
        self.dialog = None

    def ensureDialog(self):
        if self.dialog is None:
            parent = qtutils.sessionWindow()
            self.dialog = MediaInfoDialog(parent)
        return self.dialog

    def showDialog(self, event=None):
        dlg = self.ensureDialog()
        dlg.refresh(rebuildCombo=True)
        dlg.show()
        dlg.raise_()
        dlg.activateWindow()

    def onFrameChanged(self, event):
        if self.dialog and self.dialog.isVisible():
            self.dialog.onFrameChanged()
        event.reject()

    def onSourceChanged(self, event):
        if self.dialog and self.dialog.isVisible():
            self.dialog.refresh(rebuildCombo=True)
        event.reject()


def createMode():
    return MediaInfoMinorMode()
