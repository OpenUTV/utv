#
# Copyright (C) 2026 Makai Systems. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

from rv import commands, qtutils, rvtypes

try:
    from PySide6 import QtGui
    from PySide6.QtCore import Qt, QTimer
    from PySide6.QtWidgets import (
        QApplication,
        QDialog,
        QHBoxLayout,
        QHeaderView,
        QLabel,
        QLineEdit,
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
            QDialog,
            QHBoxLayout,
            QHeaderView,
            QLabel,
            QLineEdit,
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
        """)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 14, 14, 14)
        layout.setSpacing(10)

        # Header info
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
        self.tabs.addTab(self.overviewTree, "Overview")

        # Tab 2: All Attributes Tree
        self.allAttrsTree = QTreeWidget()
        self.allAttrsTree.setHeaderLabels(["Attribute", "Value"])
        self.allAttrsTree.header().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.allAttrsTree.header().setSectionResizeMode(1, QHeaderView.Stretch)
        self.allAttrsTree.setAlternatingRowColors(True)
        self.allAttrsTree.setRootIsDecorated(False)
        self.tabs.addTab(self.allAttrsTree, "All Attributes")

        # Bottom row: status, Copy All, Close
        btnLayout = QHBoxLayout()
        self.statusLabel = QLabel("")
        self.statusLabel.setStyleSheet("color: #4ec9b0; font-weight: bold;")
        btnLayout.addWidget(self.statusLabel)
        btnLayout.addStretch()

        self.copyOverviewBtn = QPushButton("Copy Overview")
        self.copyOverviewBtn.clicked.connect(self.copyOverview)
        btnLayout.addWidget(self.copyOverviewBtn)

        self.copyAllBtn = QPushButton("Copy All Metadata")
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

    def getCurrentSource(self):
        try:
            sources = commands.sourcesRendered()
            if sources:
                return sources[0].name
        except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
            pass
        try:
            nodes = commands.nodesOfType("RVSourceGroup")
            if nodes:
                return nodes[0]
        except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
            pass
        return None

    def refresh(self):
        source = self.getCurrentSource()
        if not source:
            self.fileLabel.setText("<b>File:</b> No media currently active in session")
            self.overviewTree.clear()
            self.allAttrsTree.clear()
            self.currentAttrs = []
            return

        self.currentSource = source
        try:
            attrs = commands.sourceAttributes(source)
        except (RuntimeError, ValueError, TypeError, AttributeError, KeyError):
            attrs = []

        self.currentAttrs = attrs or []
        attrDict = dict(self.currentAttrs)

        # Update file header
        filepath = attrDict.get("File", attrDict.get("Sequence", source))
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

    def copyAllMetadata(self):
        lines = []
        source = self.currentSource or "Unknown"
        lines.append(f"--- All Metadata: {source} ---")
        for k, v in self.currentAttrs:
            if k or v:
                lines.append(f"{k}: {v}")
        text = "\n".join(lines)
        QApplication.clipboard().setText(text)
        self.showStatus("✓ All metadata copied to clipboard!")


class MediaInfoMinorMode(rvtypes.MinorMode):
    """
    OpenUTV Media Information MinorMode
    """

    def __init__(self):
        super().__init__()
        globalBindings = [
            ("key-down--control--i", self.showDialog, "Show Media Information"),
            ("show-media-info-dialog", self.showDialog, "Show Media Information"),
            ("new-source", self.onSourceChanged, "Update Media Info"),
            ("source-modified", self.onSourceChanged, "Update Media Info"),
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
        dlg.refresh()
        dlg.show()
        dlg.raise_()
        dlg.activateWindow()

    def onSourceChanged(self, event):
        if self.dialog and self.dialog.isVisible():
            self.dialog.refresh()
        event.reject()


def createMode():
    return MediaInfoMinorMode()
