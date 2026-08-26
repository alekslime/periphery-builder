#!/usr/bin/env python3
"""
Periphery Welcome — first-boot tool installer.

Shows a category/tool tree (SWE, Computer Engineering, Data Science/ML,
Cybersecurity), lets the person pick what they want, and installs it via
apt / snap / pip, streaming output live. Data-driven from tools.json so the
tool list can be edited without touching this file.
"""
import json
import os
import subprocess
import sys
import webbrowser

from PyQt5.QtCore import Qt, QProcess
from PyQt5.QtGui import QPixmap, QIcon, QFont, QColor, QPalette
from PyQt5.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout, QLabel, QTreeWidget,
    QTreeWidgetItem, QPushButton, QProgressBar, QTextEdit, QSplitter,
    QMessageBox, QSizePolicy,
)

APP_DIR = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(APP_DIR, "assets")
TOOLS_JSON = os.path.join(APP_DIR, "tools.json")
MARKER_FILE = os.path.expanduser("~/.config/periphery-welcome-shown")

DARK = "#28443A"
CREAM = "#F1EEE4"
GOLD = "#D6A85D"
GOLD_HOVER = "#e0b877"

STYLESHEET = f"""
QWidget {{
    background-color: {CREAM};
    color: {DARK};
    font-family: "Noto Sans";
    font-size: 13px;
}}
QTreeWidget {{
    background-color: white;
    border: 1px solid #d8d3c4;
    border-radius: 6px;
    padding: 4px;
}}
QTreeWidget::item {{
    padding: 4px 2px;
}}
QPushButton#installBtn {{
    background-color: {GOLD};
    color: {DARK};
    font-weight: bold;
    border: none;
    border-radius: 6px;
    padding: 10px 22px;
    font-size: 14px;
}}
QPushButton#installBtn:hover {{
    background-color: {GOLD_HOVER};
}}
QPushButton#installBtn:disabled {{
    background-color: #cfcabb;
    color: #8a8578;
}}
QPushButton#skipBtn {{
    background-color: transparent;
    color: {DARK};
    border: 1px solid {DARK};
    border-radius: 6px;
    padding: 10px 18px;
}}
QPushButton#skipBtn:hover {{
    background-color: rgba(40,68,58,0.08);
}}
QProgressBar {{
    border: 1px solid #d8d3c4;
    border-radius: 5px;
    background-color: white;
    text-align: center;
    height: 18px;
}}
QProgressBar::chunk {{
    background-color: {GOLD};
    border-radius: 4px;
}}
QTextEdit#log {{
    background-color: {DARK};
    color: {CREAM};
    font-family: monospace;
    font-size: 11px;
    border-radius: 6px;
}}
QLabel#sectionTitle {{
    font-size: 15px;
    font-weight: bold;
    color: {DARK};
}}
QLabel#desc {{
    color: #55594f;
}}
"""


class InstallStep:
    """One shell command to run, with a human label for the log."""
    def __init__(self, label, program, args):
        self.label = label
        self.program = program
        self.args = args


class WelcomeWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Welcome to Periphery OS")
        self.setMinimumSize(820, 620)
        icon_path = os.path.join(ASSETS, "app-icon.png")
        if os.path.exists(icon_path):
            self.setWindowIcon(QIcon(icon_path))
        self.setStyleSheet(STYLESHEET)

        self.data = self._load_tools()
        self.queue = []
        self.current_step_index = 0
        self.total_steps = 0
        self.process = None

        self._build_ui()

    def _load_tools(self):
        with open(TOOLS_JSON, "r") as f:
            return json.load(f)

    # ---------- UI ----------

    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        root.addWidget(self._build_banner())

        body = QVBoxLayout()
        body.setContentsMargins(24, 20, 24, 20)
        body.setSpacing(14)

        intro = QLabel(
            "Pick the tools for your field. You can check a whole category, "
            "or fine-tune individual tools below it. Nothing installs until "
            "you click Install."
        )
        intro.setWordWrap(True)
        body.addWidget(intro)

        self.tree = QTreeWidget()
        self.tree.setHeaderHidden(True)
        self.tree.itemChanged.connect(self._on_item_changed)
        self.tree.currentItemChanged.connect(self._on_selection_changed)
        self._populate_tree()
        body.addWidget(self.tree, stretch=1)

        self.desc_label = QLabel(" ")
        self.desc_label.setObjectName("desc")
        self.desc_label.setWordWrap(True)
        body.addWidget(self.desc_label)

        self.log = QTextEdit()
        self.log.setObjectName("log")
        self.log.setReadOnly(True)
        self.log.setMaximumHeight(150)
        self.log.hide()
        body.addWidget(self.log)

        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.hide()
        body.addWidget(self.progress)

        button_row = QHBoxLayout()
        self.status_label = QLabel("")
        button_row.addWidget(self.status_label)
        button_row.addStretch(1)

        self.skip_btn = QPushButton("Skip for now")
        self.skip_btn.setObjectName("skipBtn")
        self.skip_btn.clicked.connect(self._on_skip)
        button_row.addWidget(self.skip_btn)

        self.install_btn = QPushButton("Install Selected")
        self.install_btn.setObjectName("installBtn")
        self.install_btn.clicked.connect(self._on_install_clicked)
        button_row.addWidget(self.install_btn)

        body.addLayout(button_row)
        root.addLayout(body)

    def _build_banner(self):
        banner = QLabel()
        banner_path = os.path.join(ASSETS, "banner.png")
        if os.path.exists(banner_path):
            pixmap = QPixmap(banner_path)
            banner.setPixmap(pixmap)
            banner.setScaledContents(True)
        banner.setFixedHeight(140)
        banner.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        return banner

    def _populate_tree(self):
        self.tree.blockSignals(True)
        self.item_meta = {}  # id(QTreeWidgetItem) -> tool dict (leaves only)

        for cat in self.data["categories"]:
            cat_item = QTreeWidgetItem(self.tree, [cat["name"]])
            cat_item.setFlags(cat_item.flags() | Qt.ItemIsUserCheckable | Qt.ItemIsAutoTristate)
            cat_item.setCheckState(0, Qt.Unchecked)
            font = cat_item.font(0)
            font.setBold(True)
            cat_item.setFont(0, font)
            cat_item.setData(0, Qt.UserRole, {"type": "category", "desc": cat["description"]})

            for tool in cat["tools"]:
                label = tool["name"]
                if tool.get("advanced"):
                    label += "  (advanced)"
                tool_item = QTreeWidgetItem(cat_item, [label])
                tool_item.setFlags(tool_item.flags() | Qt.ItemIsUserCheckable)
                tool_item.setCheckState(0, Qt.Unchecked)
                tool_item.setData(0, Qt.UserRole, {"type": "tool", **tool})

            cat_item.setExpanded(True)

        self.tree.blockSignals(False)

    def _on_item_changed(self, item, column):
        # QTreeWidget with ItemIsAutoTristate handles parent/child propagation
        # automatically; nothing extra needed here, but kept as a hook in case
        # we want live-update the install button label with a count later.
        pass

    def _on_selection_changed(self, current, previous):
        if current is None:
            self.desc_label.setText(" ")
            return
        meta = current.data(0, Qt.UserRole) or {}
        desc = meta.get("desc", "")
        self.desc_label.setText(desc)

    # ---------- Install flow ----------

    def _collect_selected_tools(self):
        selected = []
        root = self.tree.invisibleRootItem()
        for i in range(root.childCount()):
            cat_item = root.child(i)
            for j in range(cat_item.childCount()):
                tool_item = cat_item.child(j)
                if tool_item.checkState(0) == Qt.Checked:
                    selected.append(tool_item.data(0, Qt.UserRole))
        return selected

    def _on_skip(self):
        self._mark_shown()
        self.close()

    def _on_install_clicked(self):
        tools = self._collect_selected_tools()
        if not tools:
            QMessageBox.information(self, "Nothing selected",
                                     "Check at least one tool, or click Skip for now.")
            return

        apt_pkgs = []
        pip_pkgs = []
        snap_pkgs = []
        snap_classic_pkgs = []
        manual_tools = []

        for t in tools:
            method = t.get("method")
            if method == "apt":
                apt_pkgs.extend(t["package"].split())
            elif method == "pip":
                pip_pkgs.append(t["package"])
            elif method == "snap":
                if t.get("classic"):
                    snap_classic_pkgs.append(t["package"])
                else:
                    snap_pkgs.append(t["package"])
            elif method == "manual":
                manual_tools.append(t)

        self.queue = []
        if apt_pkgs:
            self.queue.append(InstallStep(
                f"Installing via apt: {' '.join(apt_pkgs)}",
                "pkexec", ["apt-get", "install", "-y"] + apt_pkgs
            ))
        if snap_pkgs:
            self.queue.append(InstallStep(
                f"Installing via snap: {' '.join(snap_pkgs)}",
                "pkexec", ["snap", "install"] + snap_pkgs
            ))
        if snap_classic_pkgs:
            self.queue.append(InstallStep(
                f"Installing via snap (classic): {' '.join(snap_classic_pkgs)}",
                "pkexec", ["snap", "install", "--classic"] + snap_classic_pkgs
            ))
        for pkg in pip_pkgs:
            self.queue.append(InstallStep(
                f"Installing via pip: {pkg}",
                "pkexec", ["pip3", "install", "--break-system-packages"] + pkg.split()
            ))

        for t in manual_tools:
            webbrowser.open(t["url"])
        if manual_tools:
            names = ", ".join(t["name"] for t in manual_tools)
            self._append_log(f"Opened browser for manual install: {names}\n")

        if not self.queue:
            self._mark_shown()
            QMessageBox.information(self, "Done", "Manual downloads opened in your browser.")
            return

        self.total_steps = len(self.queue)
        self.current_step_index = 0
        self.log.show()
        self.progress.show()
        self.progress.setValue(0)
        self.install_btn.setEnabled(False)
        self.skip_btn.setEnabled(False)
        self._run_next_step()

    def _run_next_step(self):
        if self.current_step_index >= len(self.queue):
            self._append_log("\nAll done.\n")
            self.status_label.setText("Installation complete.")
            self.progress.setValue(100)
            self.install_btn.setEnabled(True)
            self.skip_btn.setText("Close")
            self.skip_btn.setEnabled(True)
            self._mark_shown()
            return

        step = self.queue[self.current_step_index]
        self.status_label.setText(step.label)
        self._append_log(f"\n$ {step.program} {' '.join(step.args)}\n")

        self.process = QProcess(self)
        self.process.setProcessChannelMode(QProcess.MergedChannels)
        self.process.readyReadStandardOutput.connect(self._on_process_output)
        self.process.finished.connect(self._on_process_finished)
        self.process.start(step.program, step.args)

    def _on_process_output(self):
        data = bytes(self.process.readAllStandardOutput()).decode(errors="replace")
        self._append_log(data)

    def _on_process_finished(self, exit_code, exit_status):
        if exit_code != 0:
            self._append_log(f"\n[step exited with code {exit_code}]\n")
        self.current_step_index += 1
        pct = int((self.current_step_index / self.total_steps) * 100)
        self.progress.setValue(pct)
        self._run_next_step()

    def _append_log(self, text):
        self.log.moveCursor(self.log.textCursor().End)
        self.log.insertPlainText(text)
        self.log.moveCursor(self.log.textCursor().End)

    def _mark_shown(self):
        os.makedirs(os.path.dirname(MARKER_FILE), exist_ok=True)
        with open(MARKER_FILE, "w") as f:
            f.write("shown\n")


def _is_live_session():
    """
    True if we're running from the live ISO (root filesystem is an overlay
    on the squashfs), False if this is a real install (root is a normal
    filesystem on disk, e.g. ext4). Fails open (returns False) if the check
    itself can't run, so an installed system is never accidentally silenced.
    """
    try:
        result = subprocess.run(
            ["findmnt", "-no", "FSTYPE", "/"],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip() == "overlay"
    except Exception:
        return False


def main():
    if "--autostart-check" in sys.argv:
        if _is_live_session():
            sys.exit(0)  # never auto-pop on the live ISO, only on a real install
        if os.path.exists(MARKER_FILE):
            sys.exit(0)  # already shown once on this installed system

    app = QApplication(sys.argv)
    app.setApplicationName("Periphery Welcome")
    win = WelcomeWindow()
    win.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
