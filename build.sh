#!/usr/bin/env bash
#
# UTV Build Script
# Matches CI/CD execution for local development.
# Copyright (C) 2026 Makai Systems. All Rights Reserved.
#

set -e

# Default settings
BUILD_TYPE="Release"
CLEAN_BUILD=0
INSTALL=0
PACKAGE=0
INSTALL_DEPS=0
LOG_FILE=""
BMD_SDK=""
PRORES_SDK=""
CUSTOM_VERSION=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --debug) BUILD_TYPE="Debug"; shift ;;
        --release) BUILD_TYPE="Release"; shift ;;
        --clean) CLEAN_BUILD=1; shift ;;
        --install) INSTALL=1; shift ;;
        --package) PACKAGE=1; shift ;;
        --install-deps) INSTALL_DEPS=1; shift ;;
        --bmd-sdk) BMD_SDK="$2"; shift 2 ;;
        --prores-sdk) PRORES_SDK="$2"; shift 2 ;;
        --version) CUSTOM_VERSION="$2"; shift 2 ;;
        --log)
            if [[ -n "$2" && "$2" != -* ]]; then
                LOG_FILE="$2"
                shift 2
            else
                mkdir -p logs
                LOG_FILE="logs/build_$(date +%Y%m%d_%H%M%S).log"
                shift 1
            fi
            ;;
        -h|--help)
            echo "Usage: ./build.sh [OPTIONS]"
            echo "Options:"
            echo "  --debug    Build in Debug mode"
            echo "  --release  Build in Release mode (default)"
            echo "  --clean    Remove build directory and virtual environment before building"
            echo "  --install  Install the build to the _install directory"
            echo "  --package  Generate native installers (RPM/DEB/ZIP) via CPack"
            echo "  --install-deps Install core system build dependencies via dnf/apt/brew"
            echo "  --log [f]  Log output to a file (default: logs/build_TIMESTAMP.log)"
            echo "  --bmd-sdk  Path to the Blackmagic Decklink SDK zip file"
            echo "  --prores-sdk Path to the Apple ProRes SDK zip file"
            echo "  --version  Custom semantic version (e.g. 2026.1)"
            exit 0
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
done

if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Logging build output to: $LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_ROOT}/_build"
INST_DIR="${PROJECT_ROOT}/_install"
VENV_DIR="${PROJECT_ROOT}/.venv"

echo "=== UTV Build Script ==="
echo "Build Type: ${BUILD_TYPE}"

if [ "${CLEAN_BUILD}" -eq 1 ]; then
    echo "Cleaning build and environment directories..."
    rm -rf "${BUILD_DIR}"
    rm -rf "${VENV_DIR}"
fi

if [ "${INSTALL_DEPS}" -eq 1 ]; then
    echo "--- Installing System Dependencies ---"
    SUDO="sudo"
    if [ "$(id -u)" -eq 0 ] || ! command -v sudo >/dev/null 2>&1; then
        SUDO=""
    fi

    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew >/dev/null 2>&1; then
            brew install cmake ninja python@3.14
        else
            echo "WARNING: Homebrew not found. Please install it first."
        fi
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y epel-release dnf-plugins-core
        $SUDO dnf config-manager --set-enabled crb || true
        $SUDO dnf groupinstall -y "Development Tools"
        $SUDO dnf install -y cmake ninja-build git openssl-devel alsa-lib-devel libX11-devel libXext-devel libXrender-devel libXrandr-devel libXcursor-devel libXi-devel libxkbcommon-devel mesa-libGLU-devel rpm-build qt6-qtbase-devel qt6-qt5compat-devel qt6-qtsvg-devel qt6-qtdeclarative-devel qt6-qtwebengine-devel qt6-qtwebchannel-devel boost-devel openexr-devel imath-devel opencolorio-devel libraw-devel libtiff-devel libpng-devel OpenImageIO-devel openjpeg2-devel libwebp-devel yaml-cpp-devel spdlog-devel libicu-devel libjpeg-turbo-devel ffmpeg-devel
    elif command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y build-essential cmake ninja-build git curl ca-certificates libssl-dev libasound2-dev libx11-dev libxext-dev libxrender-dev libxrandr-dev libxcursor-dev libxi-dev libxkbcommon-dev libgl1-mesa-dev libglu1-mesa-dev rpm qt6-base-dev libqt6core5compat6-dev libqt6svg6-dev qt6-declarative-dev qt6-webengine-dev qt6-webchannel-dev libboost-all-dev libopenexr-dev libimath-dev libopencolorio-dev libraw-dev libtiff-dev libpng-dev libopenimageio-dev libopenjp2-7-dev libwebp-dev libyaml-cpp-dev libspdlog-dev libicu-dev libjpeg-turbo8-dev libavcodec-dev libavformat-dev libswscale-dev libavutil-dev libswresample-dev
    else
        echo "WARNING: Unsupported package manager for --install-deps."
    fi
fi

# 1. Setup Python Environment
echo "--- Setting up Python Environment ---"
if ! command -v uv >/dev/null 2>&1; then
    echo "uv not found. Installing astral uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
fi

if [ ! -d "${VENV_DIR}" ]; then
    uv venv "${VENV_DIR}" --python 3.14
fi
source "${VENV_DIR}/bin/activate"
uv pip install -r "${PROJECT_ROOT}/requirements.txt"

# 2. Locate Qt6
echo "--- Locating Qt6 ---"
if [ -z "$QT_HOME" ]; then
    if [[ "$OSTYPE" == "linux"* ]]; then
        QT_HOME=$(find /usr/lib64/qt6 /usr/lib/qt6 /usr/lib/x86_64-linux-gnu/qt6 ~/Qt*/6.* -maxdepth 4 -type d -path '*/gcc_64' 2>/dev/null | sort -V | tail -n 1)
        if [ -z "$QT_HOME" ]; then
            if [ -d "/usr/lib/x86_64-linux-gnu/qt6" ]; then
                QT_HOME="/usr/lib/x86_64-linux-gnu/qt6"
            elif [ -d "/usr/lib64/qt6" ]; then
                QT_HOME="/usr/lib64/qt6"
            else
                QT_HOME="/usr"
            fi
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if [ -d "/opt/homebrew/opt/qtbase/lib/cmake/Qt6" ]; then
            QT_HOME="/opt/homebrew/opt/qtbase"
        elif [ -d "/opt/homebrew/opt/qt/lib/cmake/Qt6" ]; then
            QT_HOME="/opt/homebrew/opt/qt"
        else
            QT_HOME=$(find /opt/homebrew/Cellar/qtbase/*/lib/cmake/Qt6 /opt/homebrew/Cellar/qt/*/lib/cmake/Qt6 -maxdepth 0 2>/dev/null | sort -V | tail -n 1 | sed 's|/lib/cmake/Qt6||')
        fi
        if [ -z "$QT_HOME" ]; then
            QT_HOME=$(find ~/Qt*/6.* -maxdepth 4 -type d -path '*/macos' 2>/dev/null | sort -V | tail -n 1)
        fi
    fi
fi

if [ -z "$QT_HOME" ]; then
    echo "ERROR: Could not find required Qt 6 installation. Please set QT_HOME."
    exit 1
fi
echo "Using QT_HOME=${QT_HOME}"

# 3. macOS Specific Fixes
if [[ "$OSTYPE" == "darwin"* ]]; then
    if command -v xcodebuild >/dev/null 2>&1; then
        XCODE_MAJOR_VERSION=$(xcodebuild -version | head -n 1 | awk '{print $2}' | cut -d. -f1)
        if [[ -n "$XCODE_MAJOR_VERSION" && "$XCODE_MAJOR_VERSION" =~ ^[0-9]+$ && "$XCODE_MAJOR_VERSION" -ge 26 ]]; then
            QT_BASE_DIR="$(dirname "$(dirname "$QT_HOME")")"
        fi
    fi
fi

# 4. Configure CMake
echo "--- Configuring CMake ---"
CMAKE_GENERATOR=${CMAKE_GENERATOR:-Ninja}
CMAKE_ARGS=(
    "-B" "${BUILD_DIR}"
    "-G" "${CMAKE_GENERATOR}"
    "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}"
    "-DRV_DEPS_QT_LOCATION=${QT_HOME}"
    "-DRV_VFX_PLATFORM=CY2026"
    "-DRV_USE_SYSTEM_DEPS=ON"
)

if [ -n "$BMD_SDK" ]; then
    CMAKE_ARGS+=("-DRV_DEPS_BMD_DECKLINK_SDK_ZIP_PATH=${BMD_SDK}")
fi

if [ -n "$PRORES_SDK" ]; then
    CMAKE_ARGS+=("-DRV_DEPS_APPLE_PRORES_SDK_ZIP_PATH=${PRORES_SDK}")
fi

if [ -n "$CUSTOM_VERSION" ]; then
    MAJOR=$(echo "$CUSTOM_VERSION" | cut -d'.' -f1)
    MINOR=$(echo "$CUSTOM_VERSION" | cut -d'.' -f2)
    CMAKE_ARGS+=("-DRV_MAJOR_VERSION=${MAJOR}" "-DRV_MINOR_VERSION=${MINOR}" "-DRV_VERSION_YEAR=${MAJOR}")
fi

# Add Windows specifics if running in MSYS/Cygwin
if [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
    CMAKE_ARGS+=("-T" "v143,version=14.40" "-A" "x64")
fi

cmake "${CMAKE_ARGS[@]}"

# 5. Build
echo "--- Building UTV ---"
PARALLELISM=${RV_BUILD_PARALLELISM:-$(python3 -c 'import os; print(os.cpu_count())')}

echo "Building dependencies target..."
cmake --build "${BUILD_DIR}" --config "${BUILD_TYPE}" --parallel "${PARALLELISM}" --target dependencies

echo "Building main_executable target..."
cmake --build "${BUILD_DIR}" --config "${BUILD_TYPE}" --parallel "${PARALLELISM}" --target main_executable

# 6. Sanitize Homebrew Links
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "--- Sanitizing Homebrew Links ---"
    python3 "${PROJECT_ROOT}/src/build/sanitize_homebrew_links.py" "${BUILD_DIR}/stage"
fi

if [ "${INSTALL}" -eq 1 ]; then
    echo "--- Installing UTV ---"
    cmake --install "${BUILD_DIR}" --prefix "${INST_DIR}" --config "${BUILD_TYPE}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "--- Sanitizing Installed Homebrew Links ---"
        python3 "${PROJECT_ROOT}/src/build/sanitize_homebrew_links.py" "${INST_DIR}"
    fi
fi

if [ "${PACKAGE}" -eq 1 ]; then
    echo "--- Packaging UTV ---"
    cd "${BUILD_DIR}"
    if [[ "$OSTYPE" == "linux"* ]]; then
        if command -v dpkg >/dev/null 2>&1; then
            cpack -G DEB -C "${BUILD_TYPE}"
        elif command -v rpmbuild >/dev/null 2>&1; then
            cpack -G RPM -C "${BUILD_TYPE}"
        else
            cpack -G TGZ -C "${BUILD_TYPE}"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        cpack -G ZIP -C "${BUILD_TYPE}"
    else
        cpack -G ZIP -C "${BUILD_TYPE}"
    fi
    cd "${PROJECT_ROOT}"
fi

echo "=== Build Complete ==="
if [ "${INSTALL}" -eq 1 ]; then
    echo "Installed to: ${INST_DIR}"
fi
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Executable is at: ${BUILD_DIR}/stage/app/UTV.app/Contents/MacOS/UTV"
else
    echo "Executable is at: ${BUILD_DIR}/stage/app/bin/utv"
fi
