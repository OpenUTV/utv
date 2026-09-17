#!/usr/bin/env python3
#
# OpenUTV Diagnostics Packager
# Cross-platform diagnostics collector for macOS, Linux, and Windows.
# Collects system info, logs, crash reports, and configs into a zip archive.
#

import os
import sys
import re
import glob
import shutil
import datetime
import tempfile
import zipfile
import subprocess
import webbrowser
import platform

TIMESTAMP = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
GITHUB_BUG_URL = "https://github.com/OpenUTV/utv/issues/new?template=bug.yml&title=[Bug]:%20"


def run_cmd(args, timeout=5):
    """Run command safely and return stdout string."""
    try:
        res = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
        return res.stdout or ""
    except Exception as e:
        return f"[Failed to run {' '.join(args)}: {e}]\n"


def collect_system_info(diag_dir):
    out_path = os.path.join(diag_dir, "system_info.txt")
    sys_name = platform.system()

    lines = [
        "=== OpenUTV Diagnostics Report ===",
        f"Generated: {datetime.datetime.now().isoformat()}",
        f"Platform: {platform.platform()}",
        f"System: {sys_name}",
        f"Release: {platform.release()}",
        f"Version: {platform.version()}",
        f"Machine: {platform.machine()}",
        f"Processor: {platform.processor()}",
        f"Python: {platform.python_version()} ({platform.python_implementation()})",
        "",
    ]

    if sys_name == "Darwin":
        lines.append("--- macOS Version ---")
        lines.append(run_cmd(["sw_vers"]))
        lines.append("--- Hardware & Kernel ---")
        lines.append(run_cmd(["uname", "-a"]))
        cpu = run_cmd(["sysctl", "-n", "machdep.cpu.brand_string"]).strip()
        lines.append(f"CPU: {cpu}")
        try:
            mem_bytes_str = run_cmd(["sysctl", "-n", "hw.memsize"]).strip()
            mem_bytes = int(mem_bytes_str)
            lines.append(f"Physical Memory: {mem_bytes // (1024**3)} GB ({mem_bytes} bytes)\n")
        except Exception:
            pass
        lines.append("--- Graphics / Metal Display Info ---")
        lines.append(run_cmd(["system_profiler", "SPDisplaysDataType", "-detailLevel", "mini"], timeout=10))

    elif sys_name == "Linux":
        lines.append("--- Linux Distribution ---")
        if os.path.exists("/etc/os-release"):
            try:
                with open("/etc/os-release") as f:
                    lines.append(f.read())
            except Exception:
                pass
        else:
            lines.append(run_cmd(["lsb_release", "-a"]))

        lines.append("--- Kernel & Hardware ---")
        lines.append(run_cmd(["uname", "-a"]))

        lines.append("--- CPU Info ---")
        if os.path.exists("/proc/cpuinfo"):
            try:
                with open("/proc/cpuinfo") as f:
                    cpu_lines = [line.strip() for line in f if "model name" in line or "cpu cores" in line]
                    lines.append("\n".join(cpu_lines[:4]))
            except Exception:
                pass

        lines.append("\n--- Memory Info ---")
        if os.path.exists("/proc/meminfo"):
            try:
                with open("/proc/meminfo") as f:
                    mem_lines = [
                        line.strip() for line in f if any(k in line for k in ("MemTotal:", "MemFree:", "MemAvailable:"))
                    ]
                    lines.append("\n".join(mem_lines))
            except Exception:
                pass

        lines.append("\n--- Graphics & Display ---")
        lines.append(f"XDG_CURRENT_DESKTOP: {os.environ.get('XDG_CURRENT_DESKTOP', '')}")
        lines.append(f"WAYLAND_DISPLAY: {os.environ.get('WAYLAND_DISPLAY', '')}")
        lines.append(f"DISPLAY: {os.environ.get('DISPLAY', '')}")

        if shutil.which("glxinfo"):
            lines.append("\n--- glxinfo -B ---")
            lines.append(run_cmd(["glxinfo", "-B"]))
        if shutil.which("vulkaninfo"):
            lines.append("\n--- vulkaninfo --summary ---")
            lines.append(run_cmd(["vulkaninfo", "--summary"]))
        if shutil.which("lspci"):
            lines.append("\n--- PCI VGA / 3D Controller ---")
            lines.append(run_cmd(["sh", "-c", "lspci -nnk | grep -iA3 -E 'vga|3d|display'"]))

    elif sys_name == "Windows":
        lines.append("--- Windows System Info ---")
        lines.append(f"Windows Version: {platform.win32_ver()}")
        lines.append(run_cmd(["cmd.exe", "/c", "wmic cpu get name,numberofcores,numberoflogicalprocessors"]))
        lines.append(
            run_cmd(
                [
                    "cmd.exe",
                    "/c",
                    "wmic path win32_VideoController get name,driverversion,adapterram,videomodedescription",
                ]
            )
        )

        try:
            import ctypes

            class MEMORYSTATUSEX(ctypes.Structure):
                _fields_ = [
                    ("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("sullAvailExtendedVirtual", ctypes.c_ulonglong),
                ]

            stat = MEMORYSTATUSEX()
            stat.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat)):
                lines.append(f"Physical Memory: {stat.ullTotalPhys // (1024**3)} GB ({stat.ullTotalPhys} bytes)")
                lines.append(f"Available Memory: {stat.ullAvailPhys // (1024**3)} GB ({stat.ullAvailPhys} bytes)")
        except Exception:
            pass

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def collect_package_info(diag_dir):
    out_path = os.path.join(diag_dir, "package_info.txt")
    sys_name = platform.system()
    lines = ["=== Package & Runtime Environment ==="]

    if sys_name == "Darwin":
        brew_bin = "/opt/homebrew/bin/brew" if os.path.exists("/opt/homebrew/bin/brew") else "/usr/local/bin/brew"
        if not os.path.exists(brew_bin):
            brew_bin = shutil.which("brew")

        if brew_bin:
            lines.append(f"Brew Path: {brew_bin}")
            lines.append(f"Brew Prefix: {run_cmd([brew_bin, '--prefix']).strip()}")
            lines.append("\n--- brew config ---")
            lines.append(run_cmd([brew_bin, "config"]))
            lines.append("\n--- Installed Multimedia Formulae ---")
            brew_list = run_cmd([brew_bin, "list", "--versions"])
            matched = [
                line
                for line in brew_list.splitlines()
                if re.match(
                    r"^(qt|boost|ffmpeg|openjpeg|openjph|openimageio|openexr|opencolorio|libraw|libpng|libtiff|jpeg-turbo|webp|imath|spdlog|yaml-cpp|pyside|python)",
                    line,
                )
            ]
            lines.append("\n".join(matched))
        else:
            lines.append("Homebrew not detected.")

    elif sys_name == "Linux":
        if shutil.which("dpkg"):
            lines.append("--- Debian/Ubuntu Packages (Qt, FFmpeg, GL) ---")
            lines.append(
                run_cmd(
                    [
                        "sh",
                        "-c",
                        "dpkg -l '*qt*' '*ffmpeg*' '*vulkan*' '*libgl*' 2>/dev/null | grep -E '^ii' | head -n 50",
                    ]
                )
            )
        elif shutil.which("rpm"):
            lines.append("--- RPM Packages ---")
            lines.append(run_cmd(["sh", "-c", "rpm -qa '*qt*' '*ffmpeg*' '*vulkan*' | head -n 50"]))

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def collect_environment(diag_dir):
    out_path = os.path.join(diag_dir, "environment.txt")
    allowed_prefixes = (
        "OPENUTV_",
        "UTV_",
        "RV_",
        "DYLD_",
        "LD_",
        "LIBGL_",
        "VK_",
        "QT_",
        "PYTHON",
        "PATH",
        "SHELL",
        "COMSPEC",
        "APPDATA",
        "LOCALAPPDATA",
        "USERPROFILE",
        "XDG_",
    )
    sensitive_words = ("KEY", "SECRET", "PASS", "TOKEN", "CREDENTIAL", "AUTH")

    lines = ["=== Sanitized Environment Variables ==="]
    for k, v in sorted(os.environ.items()):
        if any(k.startswith(p) for p in allowed_prefixes):
            if any(s in k.upper() for s in sensitive_words):
                lines.append(f"{k}=[REDACTED]")
            else:
                lines.append(f"{k}={v}")

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def copy_files(src_dir, dest_dir, pattern="*"):
    if not os.path.exists(src_dir):
        return
    os.makedirs(dest_dir, exist_ok=True)
    for p in glob.glob(os.path.join(src_dir, pattern)):
        try:
            if os.path.isfile(p):
                shutil.copy2(p, dest_dir)
            elif os.path.isdir(p):
                target = os.path.join(dest_dir, os.path.basename(p))
                if not os.path.exists(target):
                    shutil.copytree(p, target)
        except Exception:
            pass


def collect_logs(diag_dir):
    logs_dir = os.path.join(diag_dir, "logs")
    sys_name = platform.system()
    home = os.path.expanduser("~")

    if sys_name == "Darwin":
        copy_files(os.path.join(home, "Library", "Logs", "OpenUTV"), logs_dir)
        copy_files(os.path.join(home, "Library", "Logs", "UTV"), logs_dir)
    elif sys_name == "Linux":
        copy_files(os.path.join(home, ".local", "share", "OpenUTV"), logs_dir)
        copy_files(os.path.join(home, ".local", "share", "utv"), logs_dir)
        copy_files(os.path.join(home, ".openutv", "logs"), logs_dir)
        copy_files(os.path.join(home, ".rv", "logs"), logs_dir)
    elif sys_name == "Windows":
        local_app = os.environ.get("LOCALAPPDATA", os.path.join(home, "AppData", "Local"))
        app_data = os.environ.get("APPDATA", os.path.join(home, "AppData", "Roaming"))
        copy_files(os.path.join(local_app, "OpenUTV", "logs"), logs_dir)
        copy_files(os.path.join(local_app, "utv", "logs"), logs_dir)
        copy_files(os.path.join(app_data, "OpenUTV"), logs_dir)

    # Also collect any recent openutv*.log in tempdir
    tmp = tempfile.gettempdir()
    for f in glob.glob(os.path.join(tmp, "*openutv*.log")):
        try:
            shutil.copy2(f, logs_dir)
        except Exception:
            pass


def collect_crash_reports(diag_dir):
    crash_dir = os.path.join(diag_dir, "crash_reports")
    sys_name = platform.system()
    home = os.path.expanduser("~")

    if sys_name == "Darwin":
        reports = glob.glob(os.path.join(home, "Library", "Logs", "DiagnosticReports", "*UTV*"))
        reports += glob.glob(os.path.join(home, "Library", "Logs", "DiagnosticReports", "*openutv*"))
        reports.sort(key=lambda p: os.path.getmtime(p) if os.path.exists(p) else 0, reverse=True)
        os.makedirs(crash_dir, exist_ok=True)
        for r in reports[:5]:
            try:
                shutil.copy2(r, crash_dir)
            except Exception:
                pass

    elif sys_name == "Windows":
        local_app = os.environ.get("LOCALAPPDATA", os.path.join(home, "AppData", "Local"))
        dumps = glob.glob(os.path.join(local_app, "CrashDumps", "*UTV*.dmp"))
        dumps += glob.glob(os.path.join(local_app, "CrashDumps", "*openutv*.dmp"))
        dumps.sort(key=lambda p: os.path.getmtime(p) if os.path.exists(p) else 0, reverse=True)
        os.makedirs(crash_dir, exist_ok=True)
        for d in dumps[:5]:
            try:
                shutil.copy2(d, crash_dir)
            except Exception:
                pass


def collect_configs(diag_dir):
    cfg_dir = os.path.join(diag_dir, "config")
    home = os.path.expanduser("~")
    for fname in (".rvrc.mu", ".rvrc.py", ".rvrc"):
        p = os.path.join(home, fname)
        if os.path.exists(p):
            os.makedirs(cfg_dir, exist_ok=True)
            try:
                shutil.copy2(p, cfg_dir)
            except Exception:
                pass


def collect_playback_diagnostics(diag_dir):
    pb_dir = os.path.join(diag_dir, "playback_diagnostics")
    tmp = tempfile.gettempdir()
    csvs = glob.glob(os.path.join(tmp, "*playback*.csv")) + glob.glob("*playback*.csv")
    if csvs:
        os.makedirs(pb_dir, exist_ok=True)
        for c in csvs[:5]:
            try:
                shutil.copy2(c, pb_dir)
            except Exception:
                pass


def reveal_file(path):
    sys_name = platform.system()
    try:
        if sys_name == "Darwin":
            subprocess.run(["open", "-R", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif sys_name == "Windows":
            subprocess.run(
                ["explorer.exe", f"/select,{os.path.normpath(path)}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        else:
            # Linux: try nautilus or dbus or open containing dir
            folder = os.path.dirname(path)
            subprocess.run(["xdg-open", folder], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def notify_user(zip_path):
    sys_name = platform.system()
    msg = f"Diagnostics package created successfully:\n\n{zip_path}\n\nYou can attach this zip file when submitting your issue on GitHub."
    if sys_name == "Darwin":
        esc_msg = f"Saved to {os.path.basename(zip_path)} in Downloads."
        cmd = f'display notification "{esc_msg}" with title "OpenUTV Diagnostics"'
        subprocess.run(["osascript", "-e", cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif sys_name == "Windows":
        try:
            import ctypes

            # MB_OK (0) | MB_ICONINFORMATION (0x40) | MB_TOPMOST (0x40000)
            ctypes.windll.user32.MessageBoxW(0, msg, "OpenUTV Diagnostics", 0x00040040)
        except Exception:
            print(msg)
    else:
        if shutil.which("zenity"):
            subprocess.run(
                ["zenity", "--info", "--title=OpenUTV Diagnostics", f"--text={msg}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        elif shutil.which("kdialog"):
            subprocess.run(
                ["kdialog", "--msgbox", msg, "--title", "OpenUTV Diagnostics"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        else:
            print(msg)


def main():
    no_browser = "--no-browser" in sys.argv

    # 1. Setup temp collection directory
    temp_base = tempfile.mkdtemp(prefix="openutv_diag_")
    diag_folder_name = f"OpenUTV_Diagnostics_{TIMESTAMP}"
    diag_dir = os.path.join(temp_base, diag_folder_name)
    os.makedirs(diag_dir, exist_ok=True)

    # 2. Collect components
    collect_system_info(diag_dir)
    collect_package_info(diag_dir)
    collect_environment(diag_dir)
    collect_logs(diag_dir)
    collect_crash_reports(diag_dir)
    collect_configs(diag_dir)
    collect_playback_diagnostics(diag_dir)

    # 3. Create zip archive
    home = os.path.expanduser("~")
    downloads_dir = os.path.join(home, "Downloads")
    if not os.path.isdir(downloads_dir):
        downloads_dir = home

    zip_filename = f"{diag_folder_name}.zip"
    zip_path = os.path.join(downloads_dir, zip_filename)

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(diag_dir):
            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, temp_base)
                zf.write(full_path, rel_path)

    # Cleanup temp directory
    try:
        shutil.rmtree(temp_base)
    except Exception:
        pass

    # 4. Reveal zip file in Finder / Explorer / Nautilus
    reveal_file(zip_path)

    # 5. Open browser if requested
    if not no_browser:
        webbrowser.open(GITHUB_BUG_URL)

    # 6. Show confirmation dialog
    notify_user(zip_path)

    sys.exit(0)


if __name__ == "__main__":
    main()
