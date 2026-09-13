#!/bin/bash
#
# OpenUTV Diagnostics Packager
# Collects system info, Homebrew state, OpenUTV logs, and crash reports into a zip archive
# for bug reports and troubleshooting.
#

set -e

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEMP_DIR=$(mktemp -d -t openutv_diag_XXXXXX)
DIAG_DIR="${TEMP_DIR}/OpenUTV_Diagnostics_${TIMESTAMP}"
mkdir -p "${DIAG_DIR}"

echo "================================================================="
echo "  Collecting OpenUTV Diagnostic Information..."
echo "================================================================="

# 1. System Information
cat << 'EOF' > "${DIAG_DIR}/system_info.txt"
=== OpenUTV Diagnostics Report ===
Generated: $(date)

--- macOS Version ---
EOF
sw_vers >> "${DIAG_DIR}/system_info.txt" 2>&1 || true

cat << 'EOF' >> "${DIAG_DIR}/system_info.txt"

--- Hardware & Kernel ---
EOF
uname -a >> "${DIAG_DIR}/system_info.txt" 2>&1 || true
echo "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)" >> "${DIAG_DIR}/system_info.txt"
MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
MEM_GB=$(( MEM_BYTES / 1024 / 1024 / 1024 ))
echo "Physical Memory: ${MEM_GB} GB (${MEM_BYTES} bytes)" >> "${DIAG_DIR}/system_info.txt"

cat << 'EOF' >> "${DIAG_DIR}/system_info.txt"

--- Graphics / Metal Display Info ---
EOF
system_profiler SPDisplaysDataType -detailLevel mini >> "${DIAG_DIR}/system_info.txt" 2>&1 || true

# 2. Homebrew Information
cat << 'EOF' > "${DIAG_DIR}/homebrew_info.txt"
=== Homebrew Environment ===
EOF

BREW_BIN=""
if [ -x "/opt/homebrew/bin/brew" ]; then
    BREW_BIN="/opt/homebrew/bin/brew"
elif [ -x "/usr/local/bin/brew" ]; then
    BREW_BIN="/usr/local/bin/brew"
elif command -v brew &>/dev/null; then
    BREW_BIN="$(command -v brew)"
fi

if [ -n "${BREW_BIN}" ]; then
    echo "Brew Path: ${BREW_BIN}" >> "${DIAG_DIR}/homebrew_info.txt"
    echo "Brew Prefix: $("${BREW_BIN}" --prefix 2>&1 || true)" >> "${DIAG_DIR}/homebrew_info.txt"
    echo "" >> "${DIAG_DIR}/homebrew_info.txt"
    echo "--- brew config ---" >> "${DIAG_DIR}/homebrew_info.txt"
    "${BREW_BIN}" config >> "${DIAG_DIR}/homebrew_info.txt" 2>&1 || true

    echo "" >> "${DIAG_DIR}/homebrew_info.txt"
    echo "--- Installed Key Multimedia Formulas ---" >> "${DIAG_DIR}/homebrew_info.txt"
    "${BREW_BIN}" list --versions 2>/dev/null | grep -E '^(qt|boost|boost-python3|ffmpeg|ffmpeg-full|openjpeg|openjph|openimageio|openexr|opencolorio|libraw|libpng|libtiff|jpeg-turbo|webp|imath|spdlog|yaml-cpp|pyside|python)' >> "${DIAG_DIR}/homebrew_info.txt" 2>&1 || true
else
    echo "Homebrew NOT found on PATH or standard locations (/opt/homebrew, /usr/local)." >> "${DIAG_DIR}/homebrew_info.txt"
fi

# 3. OpenUTV Logs
mkdir -p "${DIAG_DIR}/logs"
if [ -d "${HOME}/Library/Logs/OpenUTV" ]; then
    cp -R "${HOME}/Library/Logs/OpenUTV/"* "${DIAG_DIR}/logs/" 2>/dev/null || true
fi

# 4. Recent Crash Reports (last 5 matching UTV or OpenUTV)
mkdir -p "${DIAG_DIR}/crash_reports"
if [ -d "${HOME}/Library/Logs/DiagnosticReports" ]; then
    ls -t "${HOME}/Library/Logs/DiagnosticReports/"UTV* 2>/dev/null | head -n 5 | while read -r crash_file; do
        if [ -f "${crash_file}" ]; then
            cp "${crash_file}" "${DIAG_DIR}/crash_reports/" 2>/dev/null || true
        fi
    done
fi

# 5. User Preferences & Config
mkdir -p "${DIAG_DIR}/config"
for cfg in "${HOME}/.rvrc.mu" "${HOME}/.rvrc.py" "${HOME}/.rvrc"; do
    if [ -f "${cfg}" ]; then
        cp "${cfg}" "${DIAG_DIR}/config/" 2>/dev/null || true
    fi
done

# 6. Relevant Environment Variables (sanitized)
cat << 'EOF' > "${DIAG_DIR}/environment.txt"
=== Environment Variables ===
EOF
env | grep -E '^(OPENUTV_|UTV_|RV_|DYLD_|QT_|PYTHON|PATH=|SHELL=)' | sort >> "${DIAG_DIR}/environment.txt" 2>&1 || true

# 7. Zip Archive
DOWNLOADS_DIR="${HOME}/Downloads"
if [ ! -d "${DOWNLOADS_DIR}" ]; then
    DOWNLOADS_DIR="${HOME}"
fi
ZIP_PATH="${DOWNLOADS_DIR}/OpenUTV_Diagnostics_${TIMESTAMP}.zip"

(cd "${TEMP_DIR}" && /usr/bin/zip -qr "${ZIP_PATH}" "OpenUTV_Diagnostics_${TIMESTAMP}")
rm -rf "${TEMP_DIR}"

echo "================================================================="
echo "  Diagnostics package saved to:"
echo "  ${ZIP_PATH}"
echo "================================================================="

# Reveal in Finder
open -R "${ZIP_PATH}" 2>/dev/null || true

# If not run with --no-browser, open GitHub issue page
if [ "$1" != "--no-browser" ]; then
    ISSUE_TITLE="[Bug]:%20"
    ISSUE_URL="https://github.com/OpenUTV/utv/issues/new?template=bug.yml&title=${ISSUE_TITLE}"
    open "${ISSUE_URL}" 2>/dev/null || true
fi

exit 0
