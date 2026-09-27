#!/usr/bin/env python3
#
# OpenUTV Supercharge FFmpeg & Professional Codecs Helper
# Cross-platform utility for macOS, Linux, and Windows to inspect, configure,
# and supercharge FFmpeg (H.265/HEVC, AAC, ProRes) and third-party SDKs
# (Blackmagic RAW, RED Digital Cinema, NDI Network Video).
#

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import webbrowser


def get_ffmpeg_info():
    """Probe ffmpeg binary and detect configuration flags."""
    candidate_bins = []
    ffmpeg_bin = shutil.which("ffmpeg")
    if ffmpeg_bin:
        candidate_bins.append(ffmpeg_bin)

    if platform.system() == "Windows":
        local_app_data = os.environ.get("LOCALAPPDATA", os.path.expanduser("~/AppData/Local"))
        user_profile = os.environ.get("USERPROFILE", os.path.expanduser("~"))

        candidate_bins.append(os.path.join(local_app_data, "Microsoft", "WinGet", "Links", "ffmpeg.exe"))

        # Scan WinGet Packages
        winget_packages = os.path.join(local_app_data, "Microsoft", "WinGet", "Packages")
        if os.path.exists(winget_packages):
            for root, dirs, files in os.walk(winget_packages):
                if "ffmpeg.exe" in files:
                    candidate_bins.append(os.path.join(root, "ffmpeg.exe"))

        # Scoop and Chocolatey
        candidate_bins.append(
            os.path.join(user_profile, "scoop", "apps", "ffmpeg-shared", "current", "bin", "ffmpeg.exe")
        )
        candidate_bins.append(os.path.join(user_profile, "scoop", "shims", "ffmpeg.exe"))
        candidate_bins.append("C:\\ProgramData\\chocolatey\\bin\\ffmpeg.exe")
        candidate_bins.append("C:\\ffmpeg\\bin\\ffmpeg.exe")
        candidate_bins.append("C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe")
        candidate_bins.append("C:\\Program Files\\OpenUTVDeps\\bin\\ffmpeg.exe")

    is_installed = False
    is_supercharged = False
    configuration = ""
    version_str = ""
    active_bin = ""

    for b in candidate_bins:
        if os.path.isfile(b) and os.access(b, os.X_OK):
            try:
                res = subprocess.run(
                    [b, "-version"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False,
                    timeout=2,
                )
                out = res.stdout or res.stderr or ""
                lower_out = out.lower()
                full_build = (
                    "full_build" in lower_out
                    or "gyan.dev" in lower_out
                    or "--enable-libx265" in lower_out
                    or "--enable-nonfree" in lower_out
                    or "--enable-libplacebo" in lower_out
                )
                if not active_bin or full_build:
                    active_bin = b
                    is_installed = True
                    for line in out.splitlines():
                        if "ffmpeg version" in line.lower() and not version_str:
                            version_str = line.strip()
                        if "configuration:" in line.lower():
                            configuration = line.strip()
                    if full_build:
                        is_supercharged = True
                        break
            except Exception:
                pass

    return {
        "installed": is_installed,
        "path": active_bin or "",
        "version": version_str,
        "configuration": configuration,
        "supercharged": is_supercharged,
    }


def check_ffmpeg_shadowed():
    """Detect if Homebrew ffmpeg-full is installed but shadowed by standard ffmpeg."""
    sys_name = platform.system()
    if sys_name not in ("Darwin", "Linux"):
        return False

    brew_bin = shutil.which("brew")
    if not brew_bin:
        for p in ("/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/home/linuxbrew/.linuxbrew/bin/brew"):
            if os.path.isfile(p) and os.access(p, os.X_OK):
                brew_bin = p
                break

    if not brew_bin:
        return False

    try:
        # Check if ffmpeg-full formula is installed
        res = subprocess.run(
            [brew_bin, "list", "--formula"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        formulas = res.stdout.split()
        if "ffmpeg-full" not in formulas:
            return False

        # If ffmpeg-full is installed, check which binary is linked
        res_which = subprocess.run(
            [brew_bin, "--prefix", "ffmpeg-full"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        full_prefix = res_which.stdout.strip()

        ffmpeg_bin = shutil.which("ffmpeg")
        if ffmpeg_bin and full_prefix:
            real_path = os.path.realpath(ffmpeg_bin)
            if full_prefix not in real_path:
                return True
    except Exception:
        pass

    return False


def get_braw_status():
    """Check if Blackmagic RAW SDK / Player is installed."""
    sys_name = platform.system()
    installed = False
    details = ""

    if sys_name == "Darwin":
        paths = [
            "/Applications/Blackmagic DaVinci Resolve/DaVinci Resolve.app",
            "/Applications/Blackmagic RAW/Blackmagic RAW Player.app",
            "/Library/Application Support/Blackmagic Design/Blackmagic RAW",
        ]
        for p in paths:
            if os.path.exists(p):
                installed = True
                details = p
                break
    elif sys_name == "Windows":
        prog_files = os.environ.get("ProgramFiles", "C:\\Program Files")
        paths = [
            os.path.join(prog_files, "Blackmagic Design", "DaVinci Resolve"),
            os.path.join(prog_files, "Blackmagic Design", "Blackmagic RAW"),
        ]
        for p in paths:
            if os.path.exists(p):
                installed = True
                details = p
                break
    else:  # Linux
        paths = [
            "/opt/resolve",
            "/usr/lib/blackmagic",
            "/usr/local/lib/blackmagic",
        ]
        for p in paths:
            if os.path.exists(p):
                installed = True
                details = p
                break

    return {"installed": installed, "details": details}


def get_red_sdk_status():
    """Check if RED Digital Cinema R3D SDK libraries are present."""
    sys_name = platform.system()
    installed = False
    details = ""

    # Check env var
    red_env = os.environ.get("RED_SDK_PATH", "")
    if red_env and os.path.exists(red_env):
        return {"installed": True, "details": f"RED_SDK_PATH={red_env}"}

    # AppData / Application Support directory
    if sys_name == "Darwin":
        home = os.path.expanduser("~")
        paths = [
            os.path.join(home, "Library", "Application Support", "OpenUTV", "RED"),
            "/Library/Application Support/OpenUTV/RED",
        ]
    elif sys_name == "Windows":
        appdata = os.environ.get("APPDATA", "")
        paths = [
            os.path.join(appdata, "OpenUTV", "RED"),
        ]
    else:
        home = os.path.expanduser("~")
        paths = [
            os.path.join(home, ".local", "share", "OpenUTV", "RED"),
            "/usr/local/lib/red",
        ]

    for p in paths:
        if os.path.exists(p):
            # Check if dynamic library exists
            for root, _, files in os.walk(p):
                for f in files:
                    lower = f.lower()
                    if "red" in lower and (".dylib" in lower or ".dll" in lower or ".so" in lower):
                        return {"installed": True, "details": os.path.join(root, f)}

    return {"installed": installed, "details": details}


def get_ndi_status():
    """Check if NewTek NDI SDK or runtime is installed."""
    sys_name = platform.system()
    installed = False
    details = ""

    if sys_name == "Darwin":
        paths = [
            "/Library/NDI SDK for Apple",
            "/Library/Application Support/NewTek/NDI",
            "/usr/local/lib/libndi.dylib",
        ]
        for p in paths:
            if os.path.exists(p):
                installed = True
                details = p
                break
    elif sys_name == "Windows":
        prog_files = os.environ.get("ProgramFiles", "C:\\Program Files")
        prog_files_x86 = os.environ.get("ProgramFiles(x86)", "C:\\Program Files (x86)")
        for base in (prog_files, prog_files_x86):
            ndi_dir = os.path.join(base, "NDI")
            if os.path.exists(ndi_dir):
                for root, _, files in os.walk(ndi_dir):
                    if "Processing.NDI.Lib.x64.dll" in files or "Processing.NDI.Lib.Advanced.x64.dll" in files:
                        return {"installed": True, "details": os.path.join(root, "Processing.NDI.Lib.x64.dll")}
                installed = True
                details = ndi_dir
                break
    else:
        paths = [
            "/usr/lib/libndi.so",
            "/usr/local/lib/libndi.so",
        ]
        for p in paths:
            if os.path.exists(p):
                installed = True
                details = p
                break

    return {"installed": installed, "details": details}


def relink_ffmpeg_full():
    """Relink Homebrew ffmpeg-full to take precedence over regular ffmpeg."""
    sys_name = platform.system()
    if sys_name not in ("Darwin", "Linux"):
        print("[ERROR] Relinking ffmpeg-full is only supported on macOS and Linux with Homebrew.")
        return False

    brew_bin = shutil.which("brew")
    if not brew_bin:
        for p in ("/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/home/linuxbrew/.linuxbrew/bin/brew"):
            if os.path.isfile(p) and os.access(p, os.X_OK):
                brew_bin = p
                break

    if not brew_bin:
        print("[ERROR] Homebrew 'brew' executable was not found on PATH.")
        return False

    print("==> Unlinking ffmpeg-full...")
    subprocess.run([brew_bin, "unlink", "ffmpeg-full"], check=False)

    print("==> Unlinking standard ffmpeg...")
    subprocess.run([brew_bin, "unlink", "ffmpeg"], check=False)

    print("==> Linking ffmpeg-full (--overwrite)...")
    res = subprocess.run([brew_bin, "link", "--overwrite", "ffmpeg-full"], text=True)

    if res.returncode == 0:
        print("[SUCCESS] ffmpeg-full is now actively linked! Full codec support is enabled.")
        return True
    else:
        print("[ERROR] Failed to relink ffmpeg-full. Please inspect Homebrew permissions.")
        return False


def get_red_dir():
    """Return local directory for RED SDK files."""
    sys_name = platform.system()
    if sys_name == "Darwin":
        return os.path.expanduser("~/Library/Application Support/OpenUTV/RED")
    elif sys_name == "Windows":
        appdata = os.environ.get("APPDATA", "")
        return os.path.join(appdata, "OpenUTV", "RED")
    else:
        return os.path.expanduser("~/.local/share/OpenUTV/RED")


def open_red_folder():
    """Open or create the local RED SDK folder."""
    red_dir = get_red_dir()
    os.makedirs(red_dir, exist_ok=True)
    sys_name = platform.system()
    print(f"Opening RED SDK directory: {red_dir}")
    if sys_name == "Darwin":
        subprocess.run(["open", red_dir])
    elif sys_name == "Windows":
        subprocess.run(["explorer", red_dir])
    else:
        subprocess.run(["xdg-open", red_dir])


def print_status_table():
    """Print user-facing status report of all codecs and SDKs."""
    ffmpeg_info = get_ffmpeg_info()
    shadowed = check_ffmpeg_shadowed()
    braw_info = get_braw_status()
    red_info = get_red_sdk_status()
    ndi_info = get_ndi_status()

    sys_name = platform.system()

    print("================================================================================")
    print("               OpenUTV Supercharged Codecs & Formats Status                     ")
    print("================================================================================")
    print(f"Operating System: {sys_name} ({platform.machine()})\n")

    # 1. FFmpeg
    print("--- [FFmpeg Multimedia Decoders] ---")
    if not ffmpeg_info["installed"]:
        print("  Status:      ⚪ NOT INSTALLED")
        print("  Resolution:  Install FFmpeg with full codec libraries.")
        if sys_name in ("Darwin", "Linux"):
            print("               brew tap homebrew-ffmpeg/ffmpeg")
            print("               brew install homebrew-ffmpeg/ffmpeg/ffmpeg-full")
        else:
            print('               winget install "FFmpeg (Shared)"   OR   scoop install ffmpeg-shared')
    elif shadowed:
        print("  Status:      🟡 SHADOWED (ffmpeg-full is installed but standard ffmpeg is active)")
        print("  Warning:     Standard ffmpeg lacks H.265/HEVC, AAC, and ProRes licenses.")
        print("  Quick Fix:   Run this script with --relink:")
        print("               openutv-supercharge-ffmpeg --relink")
    elif ffmpeg_info["supercharged"]:
        print("  Status:      🟢 SUPERCHARGED (Active with full codec support)")
        print(f"  Binary:      {ffmpeg_info['path']}")
        if ffmpeg_info["version"]:
            print(f"  Version:     {ffmpeg_info['version']}")
    else:
        print("  Status:      🟡 STANDARD (Regular distribution build active)")
        print(f"  Binary:      {ffmpeg_info['path']}")
        print("  Tip:         Upgrade to ffmpeg-full / ffmpeg-shared for H.265 and non-free codecs.")

    print()

    # 2. Blackmagic RAW
    print("--- [Blackmagic RAW (BRAW)] ---")
    if braw_info["installed"]:
        print("  Status:      🟢 AVAILABLE")
        print(f"  Path:        {braw_info['details']}")
    else:
        print("  Status:      ⚪ NOT INSTALLED (Free SDK/Player required)")
        print("  Website:     https://www.blackmagicdesign.com/support/family/professional-cameras")

    print()

    # 3. RED Digital Cinema (R3D)
    print("--- [RED Digital Cinema (R3D)] ---")
    if red_info["installed"]:
        print("  Status:      🟢 AVAILABLE")
        print(f"  Path:        {red_info['details']}")
    else:
        print("  Status:      ⚪ NOT INSTALLED (Free RED SDK required)")
        print(f"  Directory:   {get_red_dir()}")
        print("  Download:    https://www.red.com/download/r3d-sdk")

    print()

    # 4. NewTek NDI Network Video
    print("--- [NewTek NDI Network Video] ---")
    if ndi_info["installed"]:
        print("  Status:      🟢 AVAILABLE")
        print(f"  Path:        {ndi_info['details']}")
    else:
        print("  Status:      ⚪ NOT INSTALLED (Free NDI Tools/Runtime required)")
        print("  Download:    https://ndi.video/tools/")

    print("================================================================================")


def main():
    parser = argparse.ArgumentParser(description="OpenUTV Supercharge FFmpeg & Professional Codecs Helper")
    parser.add_argument(
        "--status",
        action="store_true",
        help="Print current codec and SDK installation status (default)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output status information in JSON format",
    )
    parser.add_argument(
        "--relink",
        action="store_true",
        help="Relink Homebrew ffmpeg-full over standard ffmpeg (macOS/Linux)",
    )
    parser.add_argument(
        "--open-red-folder",
        action="store_true",
        help="Open the OpenUTV RED SDK directory in system file explorer",
    )
    parser.add_argument(
        "--get-braw",
        action="store_true",
        help="Open Blackmagic RAW support page in web browser",
    )
    parser.add_argument(
        "--get-red",
        action="store_true",
        help="Open RED SDK download page in web browser",
    )
    parser.add_argument(
        "--get-ndi",
        action="store_true",
        help="Open NDI Tools download page in web browser",
    )

    args = parser.parse_args()

    if args.relink:
        success = relink_ffmpeg_full()
        sys.exit(0 if success else 1)

    if args.open_red_folder:
        open_red_folder()
        sys.exit(0)

    if args.get_braw:
        webbrowser.open("https://www.blackmagicdesign.com/support/family/professional-cameras")
        sys.exit(0)

    if args.get_red:
        webbrowser.open("https://www.red.com/download/r3d-sdk")
        sys.exit(0)

    if args.get_ndi:
        webbrowser.open("https://ndi.video/tools/")
        sys.exit(0)

    if args.json:
        data = {
            "os": platform.system(),
            "arch": platform.machine(),
            "ffmpeg": get_ffmpeg_info(),
            "ffmpeg_shadowed": check_ffmpeg_shadowed(),
            "braw": get_braw_status(),
            "red": get_red_sdk_status(),
            "ndi": get_ndi_status(),
        }
        print(json.dumps(data, indent=2))
        sys.exit(0)

    # Default action: print status table
    print_status_table()


if __name__ == "__main__":
    main()
