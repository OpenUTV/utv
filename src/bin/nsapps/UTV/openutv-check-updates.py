#!/usr/bin/env python3
#
# OpenUTV Version Update Checker
# Cross-platform update checker for macOS, Linux, and Windows.
# Checks GitHub Releases API for new OpenUTV releases and prompts the user.
# Supports launch-time checks, snooze (1 day / 1 week), version skipping,
# and Windows OpenUTVDeps dependency updates.
#

import os
import sys
import json
import re
import time
import shutil
import subprocess
import webbrowser
import platform
import urllib.request
import urllib.error

APP_NAME = "OpenUTV"
GITHUB_UTV_API = "https://api.github.com/repos/OpenUTV/utv/releases/latest"
GITHUB_UTV_URL = "https://github.com/OpenUTV/utv/releases/latest"
GITHUB_DEPS_API = "https://api.github.com/repos/OpenUTV/utv-dependencies/releases/latest"
GITHUB_DEPS_URL = "https://github.com/OpenUTV/utv-dependencies/releases/latest"
CURRENT_FALLBACK_VERSION = "2026.8"


def get_settings_file():
    """Return path to user update settings file based on platform."""
    sys_name = platform.system()
    if sys_name == "Darwin":
        base = os.path.expanduser("~/Library/Application Support/OpenUTV")
    elif sys_name == "Windows":
        base = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "OpenUTV")
    else:
        base = os.path.expanduser("~/.config/openutv")

    try:
        os.makedirs(base, exist_ok=True)
    except Exception:
        pass
    return os.path.join(base, "update_settings.json")


def load_settings():
    """Load settings from JSON file, returning defaults if not found."""
    path = get_settings_file()
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "check_on_startup": True,
        "snooze_until": 0,
        "ignored_versions": [],
        "snooze_deps_until": 0,
        "ignored_deps_versions": [],
        "last_check_timestamp": 0,
    }


def save_settings(settings):
    """Persist settings to JSON file."""
    path = get_settings_file()
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)
    except Exception:
        pass


def snooze_update(days=1, is_deps=False):
    """Snooze alerts for a specified number of days."""
    settings = load_settings()
    key = "snooze_deps_until" if is_deps else "snooze_until"
    settings[key] = int(time.time() + (days * 86400))
    save_settings(settings)


def skip_version(version_tag, is_deps=False):
    """Add a version to the ignored versions list so it is not shown again."""
    settings = load_settings()
    key = "ignored_deps_versions" if is_deps else "ignored_versions"
    ignored = settings.get(key, [])
    if version_tag not in ignored:
        ignored.append(version_tag)
    settings[key] = ignored
    save_settings(settings)


def is_version_snoozed(is_deps=False):
    """Check if updates are currently snoozed."""
    settings = load_settings()
    key = "snooze_deps_until" if is_deps else "snooze_until"
    return time.time() < settings.get(key, 0)


def is_version_ignored(version_tag, is_deps=False):
    """Check if a specific version has been skipped by the user."""
    settings = load_settings()
    key = "ignored_deps_versions" if is_deps else "ignored_versions"
    return version_tag in settings.get(key, [])


def get_current_version():
    """Determine current OpenUTV version."""
    # 1. Check command line arguments for --current-version
    for i, arg in enumerate(sys.argv):
        if arg == "--current-version" and i + 1 < len(sys.argv):
            return sys.argv[i + 1]

    # 2. Try macOS Info.plist if running from an app bundle
    app_dir = os.path.dirname(os.path.abspath(__file__))
    info_plist = os.path.normpath(os.path.join(app_dir, "..", "Info.plist"))
    if os.path.exists(info_plist):
        try:
            out = subprocess.check_output(
                ["defaults", "read", info_plist, "CFBundleShortVersionString"],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            if out:
                return out
        except Exception:
            pass

    # 3. Try running UTV -version if binary is next to this script
    bin_name = "UTV.exe" if platform.system() == "Windows" else "UTV"
    bin_path = os.path.join(app_dir, bin_name)
    if os.path.exists(bin_path) and os.access(bin_path, os.X_OK):
        try:
            out = subprocess.check_output([bin_path, "-version"], stderr=subprocess.DEVNULL, text=True).strip()
            if out:
                return out
        except Exception:
            pass

    return CURRENT_FALLBACK_VERSION


def parse_version(v_str):
    """Extract numeric components from a version string (e.g. 'v2026.8.0' -> (2026, 8, 0))."""
    if not v_str:
        return (0,)
    clean = v_str.lstrip("vV").strip()
    nums = re.findall(r"\d+", clean)
    if nums:
        return tuple(int(n) for n in nums)
    return (0,)


def show_alert(title, message, is_warning=False):
    """Display a simple cross-platform information or warning dialog."""
    sys_name = platform.system()
    if sys_name == "Darwin":
        alert_type = "as warning" if is_warning else "as informational"
        esc_title = title.replace('"', '\\"')
        esc_msg = message.replace('"', '\\"')
        cmd = f'display alert "{esc_title}" message "{esc_msg}" {alert_type}'
        subprocess.run(["osascript", "-e", cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif sys_name == "Windows":
        try:
            import ctypes

            flags = 0x30 if is_warning else 0x40  # MB_ICONWARNING or MB_ICONINFORMATION
            flags |= 0x00040000  # MB_TOPMOST
            ctypes.windll.user32.MessageBoxW(0, message, title, flags)
        except Exception:
            print(f"[{title}] {message}", file=sys.stderr if is_warning else sys.stdout)
    else:
        # Linux
        if shutil.which("zenity"):
            flag = "--warning" if is_warning else "--info"
            subprocess.run(
                ["zenity", flag, f"--title={title}", f"--text={message}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        elif shutil.which("kdialog"):
            flag = "--sorry" if is_warning else "--msgbox"
            subprocess.run(
                ["kdialog", flag, message, f"--title={title}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        else:
            print(f"[{title}] {message}", file=sys.stderr if is_warning else sys.stdout)


def get_installed_windows_deps_version():
    """Detect installed OpenUTVDeps version on Windows from directories and registry."""
    if platform.system() != "Windows":
        return None

    import glob

    found = []

    # 1. Directory names under Program Files
    patterns = [
        r"C:\Program Files\OpenUTVDeps *",
        r"C:\Program Files\OpenUTVDeps*",
        os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "OpenUTVDeps*"),
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "OpenUTVDeps*"),
        r"C:\OpenUTVDeps*",
    ]
    for pat in patterns:
        for p in glob.glob(pat):
            if os.path.isdir(p):
                base = os.path.basename(p)
                m = re.search(r"(\d+(?:\.\d+)*)", base)
                if m:
                    found.append(m.group(1))

    # 2. Windows Uninstall Registry
    try:
        import winreg

        subkeys = [
            r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        ]
        for root in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
            for sub in subkeys:
                try:
                    with winreg.OpenKey(root, sub) as key:
                        count = winreg.QueryInfoKey(key)[0]
                        for i in range(count):
                            try:
                                subname = winreg.EnumKey(key, i)
                                with winreg.OpenKey(key, subname) as appkey:
                                    disp_name, _ = winreg.QueryValueEx(appkey, "DisplayName")
                                    if "OpenUTVDeps" in disp_name:
                                        try:
                                            ver, _ = winreg.QueryValueEx(appkey, "DisplayVersion")
                                            if ver:
                                                found.append(ver)
                                        except Exception:
                                            m = re.search(r"(\d+(?:\.\d+)*)", disp_name)
                                            if m:
                                                found.append(m.group(1))
                            except Exception:
                                pass
                except Exception:
                    pass
    except Exception:
        pass

    if not found:
        return None

    found.sort(key=parse_version, reverse=True)
    return found[0]


def prompt_update_available(latest_tag, current_ver, is_deps=False, download_url=None):
    """
    Prompt the user that an update is available, offering choices:
    - Upgrade / Download Now
    - Remind Me Tomorrow (1 Day)
    - Remind Me in 1 Week (7 Days)
    - Skip This Version
    """
    sys_name = platform.system()
    item_name = "OpenUTV Dependencies" if is_deps else "OpenUTV"
    target_url = download_url if download_url else (GITHUB_DEPS_URL if is_deps else GITHUB_UTV_URL)

    # -------------------------------------------------------------------------
    # macOS
    # -------------------------------------------------------------------------
    if sys_name == "Darwin":
        has_cask = False
        if not is_deps:
            brew_bin = "/opt/homebrew/bin/brew" if os.path.exists("/opt/homebrew/bin/brew") else "/usr/local/bin/brew"
            if not os.path.exists(brew_bin):
                brew_bin = shutil.which("brew")
            if brew_bin:
                res = subprocess.run(
                    [brew_bin, "list", "--cask", "utv"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                if res.returncode == 0:
                    has_cask = True

        upgrade_label = "Upgrade via Homebrew" if has_cask else "Download Update"
        esc_title = f"{item_name} Update Available"
        esc_msg = (
            f"{item_name} {latest_tag} is now available (you are running {current_ver}).\\n\\n"
            f"Would you like to install the update now?"
        )

        # Primary prompt
        cmd = (
            f'button returned of (display alert "{esc_title}" '
            f'message "{esc_msg}" '
            f'buttons {{"{upgrade_label}", "Remind Later...", "Skip This Version"}} '
            f"default button 1 cancel button 2)"
        )
        p = subprocess.run(["osascript", "-e", cmd], capture_output=True, text=True)
        choice = p.stdout.strip()

        if choice == upgrade_label:
            if has_cask:
                script_path = "/tmp/openutv_upgrade.command"
                with open(script_path, "w") as f:
                    f.write("""#!/bin/bash
clear 2>/dev/null || true
echo "================================================================="
echo "  Upgrading OpenUTV via Homebrew Cask..."
echo "================================================================="
echo ""
if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
brew upgrade --cask utv
echo ""
echo "================================================================="
echo "  Upgrade finished! You can now restart OpenUTV."
echo "================================================================="
read -n 1 -s -r -p "Press any key to close..." && exit 0
""")
                os.chmod(script_path, 0o755)
                subprocess.run(["open", script_path])
            else:
                webbrowser.open(target_url)

        elif choice == "Remind Later...":
            remind_cmd = (
                f'button returned of (display alert "Remind Later" '
                f'message "When would you like to be reminded about {item_name} {latest_tag}?" '
                f'buttons {{"Tomorrow (1 Day)", "In 1 Week", "Cancel"}} '
                f"default button 1 cancel button 3)"
            )
            p_remind = subprocess.run(["osascript", "-e", remind_cmd], capture_output=True, text=True)
            remind_choice = p_remind.stdout.strip()
            if remind_choice == "Tomorrow (1 Day)":
                snooze_update(days=1, is_deps=is_deps)
            elif remind_choice == "In 1 Week":
                snooze_update(days=7, is_deps=is_deps)

        elif choice == "Skip This Version":
            skip_version(latest_tag, is_deps=is_deps)

    # -------------------------------------------------------------------------
    # Windows
    # -------------------------------------------------------------------------
    elif sys_name == "Windows":
        # Check if installed via Chocolatey or Scoop (only for app)
        has_choco = False
        has_scoop = False
        if not is_deps:
            if shutil.which("choco"):
                r = subprocess.run(
                    ["choco", "list", "--local-only", "openutv"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                )
                if "openutv" in r.stdout.lower():
                    has_choco = True
            if shutil.which("scoop"):
                r = subprocess.run(
                    ["scoop", "list", "openutv"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                )
                if "openutv" in r.stdout.lower():
                    has_scoop = True

        # Try interactive Tkinter window for multi-choice support
        chosen_action = [None]
        try:
            import tkinter as tk
            from tkinter import ttk

            root = tk.Tk()
            root.title(f"{item_name} Update Available")
            root.attributes("-topmost", True)
            root.resizable(False, False)

            # Styling
            padding_frame = ttk.Frame(root, padding="16 16 16 16")
            padding_frame.grid(column=0, row=0, sticky="NSEW")

            header_label = ttk.Label(
                padding_frame,
                text=f"{item_name} {latest_tag} is available!",
                font=("Segoe UI", 12, "bold"),
            )
            header_label.grid(column=0, row=0, columnspan=2, sticky="W", pady=(0, 6))

            desc_text = (
                f"You are currently running version {current_ver}.\n\n"
                f"Would you like to install the new version now, or be reminded later?"
            )
            desc_label = ttk.Label(padding_frame, text=desc_text, font=("Segoe UI", 10))
            desc_label.grid(column=0, row=1, columnspan=2, sticky="W", pady=(0, 16))

            btn_frame = ttk.Frame(padding_frame)
            btn_frame.grid(column=0, row=2, columnspan=2, sticky="E")

            def on_action(act):
                chosen_action[0] = act
                root.destroy()

            upgrade_btn_text = (
                "Upgrade via Chocolatey" if has_choco else ("Upgrade via Scoop" if has_scoop else "Download Update")
            )
            btn_upgrade = ttk.Button(btn_frame, text=upgrade_btn_text, command=lambda: on_action("upgrade"))
            btn_upgrade.pack(side="left", padx=4)

            btn_tomorrow = ttk.Button(btn_frame, text="Remind Tomorrow", command=lambda: on_action("tomorrow"))
            btn_tomorrow.pack(side="left", padx=4)

            btn_week = ttk.Button(btn_frame, text="Remind in 1 Week", command=lambda: on_action("week"))
            btn_week.pack(side="left", padx=4)

            btn_skip = ttk.Button(btn_frame, text="Skip Version", command=lambda: on_action("skip"))
            btn_skip.pack(side="left", padx=4)

            # Center window on screen
            root.update_idletasks()
            w = root.winfo_width()
            h = root.winfo_height()
            ws = root.winfo_screenwidth()
            hs = root.winfo_screenheight()
            x = (ws / 2) - (w / 2)
            y = (hs / 2) - (h / 2)
            root.geometry("+%d+%d" % (x, y))

            root.mainloop()

        except Exception:
            # Fallback to MessageBoxW if Tkinter is not available
            try:
                import ctypes

                flags = 0x00000004 | 0x00000020 | 0x00040000  # MB_YESNO | MB_ICONQUESTION | MB_TOPMOST
                msg = (
                    f"{item_name} {latest_tag} is now available (you are running {current_ver}).\n\n"
                    f"Would you like to open the release download page now?"
                )
                ret = ctypes.windll.user32.MessageBoxW(0, msg, f"{item_name} Update Available", flags)
                if ret == 6:  # IDYES
                    chosen_action[0] = "upgrade"
                else:
                    chosen_action[0] = "tomorrow"
            except Exception:
                chosen_action[0] = "upgrade"

        act = chosen_action[0]
        if act == "upgrade":
            if has_choco:
                subprocess.Popen(["powershell.exe", "-NoExit", "-Command", "choco upgrade openutv -y"])
            elif has_scoop:
                subprocess.Popen(["powershell.exe", "-NoExit", "-Command", "scoop update openutv"])
            else:
                webbrowser.open(target_url)
        elif act == "tomorrow":
            snooze_update(days=1, is_deps=is_deps)
        elif act == "week":
            snooze_update(days=7, is_deps=is_deps)
        elif act == "skip":
            skip_version(latest_tag, is_deps=is_deps)

    # -------------------------------------------------------------------------
    # Linux
    # -------------------------------------------------------------------------
    else:
        chosen = None
        msg = f"{item_name} {latest_tag} is available (currently running {current_ver}).\\nChoose an action:"

        if shutil.which("zenity"):
            res = subprocess.run(
                [
                    "zenity",
                    "--list",
                    "--radiolist",
                    f"--title={item_name} Update Available",
                    f"--text={msg}",
                    "--column=Select",
                    "--column=Action",
                    "TRUE",
                    "Download Update Now",
                    "FALSE",
                    "Remind Me Tomorrow (1 Day)",
                    "FALSE",
                    "Remind Me in 1 Week",
                    "FALSE",
                    "Skip This Version",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            chosen = res.stdout.strip()
        elif shutil.which("kdialog"):
            res = subprocess.run(
                [
                    "kdialog",
                    "--radiolist",
                    msg,
                    "download",
                    "Download Update Now",
                    "on",
                    "tomorrow",
                    "Remind Me Tomorrow (1 Day)",
                    "off",
                    "week",
                    "Remind Me in 1 Week",
                    "off",
                    "skip",
                    "Skip This Version",
                    "--title",
                    f"{item_name} Update Available",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            chosen = res.stdout.strip()

        if chosen in ("Download Update Now", "download"):
            webbrowser.open(target_url)
        elif chosen in ("Remind Me Tomorrow (1 Day)", "tomorrow"):
            snooze_update(days=1, is_deps=is_deps)
        elif chosen in ("Remind Me in 1 Week", "week"):
            snooze_update(days=7, is_deps=is_deps)
        elif chosen in ("Skip This Version", "skip"):
            skip_version(latest_tag, is_deps=is_deps)
        elif chosen is None and not sys_name.startswith("Linux"):
            webbrowser.open(target_url)


def query_latest_release(api_url, current_version):
    """Query GitHub API for latest release info."""
    req = urllib.request.Request(
        api_url,
        headers={"User-Agent": f"OpenUTV-UpdateChecker/{current_version}"},
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        data = json.loads(response.read().decode("utf-8"))
        latest_tag = data.get("tag_name", "").strip()
        html_url = data.get("html_url", "")
        assets = data.get("assets", [])

        # Look for MSI asset if available
        msi_url = None
        for a in assets:
            dl_url = a.get("browser_download_url", "")
            if dl_url.endswith(".msi"):
                msi_url = dl_url
                break

        return latest_tag, html_url, msi_url


def main():
    interactive = "--interactive" in sys.argv
    startup = "--startup" in sys.argv
    current_version = get_current_version()

    # If launched on startup: wait 3 seconds so the main application window renders first
    if startup:
        time.sleep(3)

    settings = load_settings()
    if startup and not settings.get("check_on_startup", True):
        sys.exit(0)

    # =========================================================================
    # 1. Check OpenUTV Application Updates
    # =========================================================================
    check_app = True
    if startup and is_version_snoozed(is_deps=False):
        check_app = False

    app_update_found = False

    if check_app:
        try:
            latest_tag, html_url, _ = query_latest_release(GITHUB_UTV_API, current_version)
            if latest_tag:
                current_parsed = parse_version(current_version)
                latest_parsed = parse_version(latest_tag)

                if latest_parsed > current_parsed:
                    if not startup or not is_version_ignored(latest_tag, is_deps=False):
                        app_update_found = True
                        prompt_update_available(latest_tag, current_version, is_deps=False, download_url=html_url)
                else:
                    if interactive:
                        show_alert(
                            "OpenUTV Updates",
                            f"OpenUTV is up to date (version {current_version}).",
                            is_warning=False,
                        )
        except Exception:
            if interactive:
                show_alert(
                    "OpenUTV Updates",
                    "Unable to check for updates at this time. Please check your internet connection.",
                    is_warning=True,
                )
            if startup:
                sys.exit(0)

    # =========================================================================
    # 2. Check Windows Dependencies Updates (OpenUTVDeps)
    # =========================================================================
    if platform.system() == "Windows":
        check_deps = True
        if startup and is_version_snoozed(is_deps=True):
            check_deps = False

        if check_deps:
            installed_deps = get_installed_windows_deps_version()
            if installed_deps:
                try:
                    latest_deps_tag, deps_html_url, deps_msi_url = query_latest_release(
                        GITHUB_DEPS_API, current_version
                    )
                    if latest_deps_tag:
                        installed_deps_parsed = parse_version(installed_deps)
                        latest_deps_parsed = parse_version(latest_deps_tag)

                        if latest_deps_parsed > installed_deps_parsed:
                            if not startup or not is_version_ignored(latest_deps_tag, is_deps=True):
                                dl_target = deps_msi_url if deps_msi_url else deps_html_url
                                prompt_update_available(
                                    latest_deps_tag,
                                    installed_deps,
                                    is_deps=True,
                                    download_url=dl_target,
                                )
                        else:
                            if interactive and not app_update_found:
                                show_alert(
                                    "OpenUTV Dependencies",
                                    f"OpenUTVDeps runtime is also up to date (version {installed_deps}).",
                                    is_warning=False,
                                )
                except Exception:
                    pass

    # Record last check timestamp
    settings = load_settings()
    settings["last_check_timestamp"] = int(time.time())
    save_settings(settings)

    sys.exit(0)


if __name__ == "__main__":
    main()
