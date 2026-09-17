#!/usr/bin/env python3
#
# OpenUTV Version Update Checker
# Cross-platform update checker for macOS, Linux, and Windows.
# Checks GitHub Releases API for new OpenUTV releases and prompts the user.
#

import os
import sys
import json
import re
import shutil
import subprocess
import webbrowser
import platform
import urllib.request
import urllib.error

GITHUB_RELEASES_API = "https://api.github.com/repos/OpenUTV/utv/releases/latest"
GITHUB_RELEASES_URL = "https://github.com/OpenUTV/utv/releases/latest"
CURRENT_FALLBACK_VERSION = "2026.2"


def get_current_version():
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
                ["defaults", "read", info_plist, "CFBundleShortVersionString"], stderr=subprocess.DEVNULL, text=True
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
    """Extract numeric components from a version string (e.g. 'v2026.2.1' -> (2026, 2, 1))."""
    if not v_str:
        return (0,)
    clean = v_str.lstrip("vV").strip()
    nums = re.findall(r"\d+", clean)
    if nums:
        return tuple(int(n) for n in nums)
    return (0,)


def show_alert(title, message, is_warning=False):
    """Display a cross-platform information or warning dialog."""
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
                ["kdialog", flag, message, f"--title={title}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        else:
            print(f"[{title}] {message}", file=sys.stderr if is_warning else sys.stdout)


def prompt_update_available(latest_tag, current_ver):
    """Prompt the user that an update is available and offer download/upgrade."""
    sys_name = platform.system()

    if sys_name == "Darwin":
        # Check if installed via Homebrew Cask
        has_cask = False
        brew_bin = "/opt/homebrew/bin/brew" if os.path.exists("/opt/homebrew/bin/brew") else "/usr/local/bin/brew"
        if not os.path.exists(brew_bin):
            brew_bin = shutil.which("brew")

        if brew_bin:
            res = subprocess.run(
                [brew_bin, "list", "--cask", "utv"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            if res.returncode == 0:
                has_cask = True

        if has_cask:
            cmd = (
                f'button returned of (display alert "OpenUTV Update Available" '
                f'message "OpenUTV {latest_tag} is now available (you are currently running {current_ver}). '
                f'Would you like to upgrade now via Homebrew?" '
                f'buttons {{"Upgrade via Homebrew", "View on GitHub", "Later"}} default button 1)'
            )
            p = subprocess.run(["osascript", "-e", cmd], capture_output=True, text=True)
            choice = p.stdout.strip()
            if choice == "Upgrade via Homebrew":
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
            elif choice == "View on GitHub":
                webbrowser.open(GITHUB_RELEASES_URL)
        else:
            cmd = (
                f'button returned of (display alert "OpenUTV Update Available" '
                f'message "OpenUTV {latest_tag} is now available (you are currently running {current_ver})." '
                f'buttons {{"Download from GitHub", "Later"}} default button 1)'
            )
            p = subprocess.run(["osascript", "-e", cmd], capture_output=True, text=True)
            choice = p.stdout.strip()
            if choice == "Download from GitHub":
                webbrowser.open(GITHUB_RELEASES_URL)

    elif sys_name == "Windows":
        try:
            import ctypes

            # MB_YESNO (0x04) | MB_ICONQUESTION (0x20) | MB_TOPMOST (0x40000)
            flags = 0x00000004 | 0x00000020 | 0x00040000
            msg = (
                f"OpenUTV {latest_tag} is now available (you are currently running {current_ver}).\n\n"
                "Would you like to open the GitHub releases page to download the new version?"
            )
            ret = ctypes.windll.user32.MessageBoxW(0, msg, "OpenUTV Update Available", flags)
            # IDYES is 6
            if ret == 6:
                webbrowser.open(GITHUB_RELEASES_URL)
        except Exception:
            webbrowser.open(GITHUB_RELEASES_URL)

    else:
        # Linux
        prompted = False
        msg = (
            f"OpenUTV {latest_tag} is now available (you are currently running {current_ver}).\n\n"
            "Would you like to open the GitHub releases page to download the new version?"
        )
        if shutil.which("zenity"):
            res = subprocess.run(
                [
                    "zenity",
                    "--question",
                    "--title=OpenUTV Update Available",
                    f"--text={msg}",
                    "--ok-label=Download",
                    "--cancel-label=Later",
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            prompted = True
            if res.returncode == 0:
                webbrowser.open(GITHUB_RELEASES_URL)
        elif shutil.which("kdialog"):
            res = subprocess.run(
                ["kdialog", "--yesno", msg, "--title", "OpenUTV Update Available"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            prompted = True
            if res.returncode == 0:
                webbrowser.open(GITHUB_RELEASES_URL)

        if not prompted:
            webbrowser.open(GITHUB_RELEASES_URL)


def main():
    interactive = "--interactive" in sys.argv
    current_version = get_current_version()

    # Query GitHub API
    req = urllib.request.Request(
        GITHUB_RELEASES_API, headers={"User-Agent": f"OpenUTV-UpdateChecker/{current_version}"}
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode("utf-8"))
            latest_tag = data.get("tag_name", "").strip()
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, Exception):
        if interactive:
            show_alert(
                "OpenUTV Updates",
                "Unable to check for updates at this time. Please check your internet connection.",
                is_warning=True,
            )
        sys.exit(0)

    if not latest_tag:
        if interactive:
            show_alert(
                "OpenUTV Updates",
                "Unable to check for updates at this time. Please check your internet connection.",
                is_warning=True,
            )
        sys.exit(0)

    current_parsed = parse_version(current_version)
    latest_parsed = parse_version(latest_tag)

    if latest_parsed > current_parsed:
        prompt_update_available(latest_tag, current_version)
    else:
        if interactive:
            show_alert("OpenUTV Updates", f"OpenUTV is up to date (version {current_version}).", is_warning=False)

    sys.exit(0)


if __name__ == "__main__":
    main()
