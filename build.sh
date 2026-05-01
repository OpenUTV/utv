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
PYTHON_VERSION="3.13"
GCC_VERSION="15"

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
VENV_DIR="${PROJECT_ROOT}/.venv-$OSTYPE"

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

    # Install specific CMake version natively on Linux if not present or too old
    if [[ "$OSTYPE" != "darwin"* ]] && [[ "$OSTYPE" != "msys"* ]]; then
        # CMAKE_REQ_VER="4.2.3"
        CMAKE_REQ_VER="3.31.12"
        # Check if cmake exists and its version
        CURRENT_CMAKE_VER=$(cmake --version 2>/dev/null | head -n1 | awk '{print $3}')
        if [[ "$CURRENT_CMAKE_VER" != "$CMAKE_REQ_VER" ]]; then
            echo "--- Installing CMake ${CMAKE_REQ_VER} (Linux x86_64) ---"
            curl -L -o /tmp/cmake.tar.gz "https://github.com/Kitware/CMake/releases/download/v${CMAKE_REQ_VER}/cmake-${CMAKE_REQ_VER}-linux-x86_64.tar.gz"
            $SUDO tar -zxvf /tmp/cmake.tar.gz -C /usr/local --strip-components=1
            rm /tmp/cmake.tar.gz
        fi
    fi

    # macOS setup
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew >/dev/null 2>&1; then
            brew install cmake ninja python@${PYTHON_VERSION}
        else
            echo "WARNING: Homebrew not found. Please install it first."
        fi
    # RHEL / Rocky Setup
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y epel-release dnf-plugins-core
        $SUDO dnf config-manager --set-enabled crb || true
        $SUDO dnf install -y --nogpgcheck https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm || true
        $SUDO dnf groupinstall -y "Development Tools"
        $SUDO dnf install -y --allowerasing \
                alsa-lib-devel \
                boost-devel \
                curl \
                doctest-devel \
                ffmpeg-devel \
                git \
                glew-devel \
                imath-devel \
                libdav1d-devel \
                libicu-devel \
                libjpeg-turbo-devel \
                libopenjph-devel \
                libpng-devel \
                LibRaw-devel \
                libtiff-devel \
                libwebp-devel \
                libX11-devel \
                libXcursor-devel \
                libXext-devel \
                libXi-devel \
                libxkbcommon-devel \
                libXrandr-devel \
                libXrender-devel \
                mesa-libGLU-devel \
                ninja-build \
                openexr-devel \
                OpenImageIO-devel \
                openjpeg2-devel \
                openssl-devel \
                perl \
                pkgconf-pkg-config \
                qt6-qt5compat-devel \
                qt6-qtbase-devel \
                qt6-qtdeclarative-devel \
                qt6-qtsvg-devel \
                qt6-qtwebchannel-devel \
                qt6-qtwebengine-devel \
                rpm-build \
                spdlog-devel \
                tar \
                unzip \
                yaml-cpp-devel \
                zip

        # --- Bootstrapping vcpkg for missing Rocky dependencies (OpenColorIO) ---
        VCPKG_DIR="${PROJECT_ROOT}/vcpkg"
        if [ ! -d "$VCPKG_DIR" ]; then
            echo "--- Bootstrapping vcpkg for missing Rocky dependencies ---"
            git clone https://github.com/microsoft/vcpkg.git "$VCPKG_DIR"
            "$VCPKG_DIR/bootstrap-vcpkg.sh" -disableMetrics
            echo "set(VCPKG_BUILD_TYPE release)" >> "$VCPKG_DIR/triplets/x64-linux.cmake"
        fi
        export VCPKG_BUILD_TYPE="release"
        echo "Installing missing dependencies via vcpkg (Release only)..."
        "$VCPKG_DIR/vcpkg" install "opencolorio"
    # Ubuntu Setup
    elif command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y \
                bison \
                build-essential \
                ca-certificates \
                curl \
                doctest-dev \
                flex \
                git \
                glew-utils \
                libaio-dev \
                libasound2-dev \
                libavcodec-dev \
                libavformat-dev \
                libavutil-dev \
                libboost-all-dev \
                libdav1d-dev \
                libfreetype-dev \
                libgl1-mesa-dev \
                libglew-dev \
                libglew-dev \
                libglu1-mesa-dev \
                libicu-dev \
                libimath-dev \
                libopencolorio-dev \
                libopencv-dev \
                libopenexr-dev \
                libopenjp2-7-dev \
                libosmesa6-dev \
                libpng-dev \
                libraw-dev \
                libspdlog-dev \
                libssl-dev \
                libswresample-dev \
                libswscale-dev \
                libtiff-dev \
                libturbojpeg0-dev \
                libwebp-dev \
                libx11-dev \
                libxcursor-dev \
                libxext-dev \
                libxi-dev \
                libxkbcommon-dev \
                libxrandr-dev \
                libxrender-dev \
                libyaml-cpp-dev \
                ninja-build \
                pkg-config \
                qt6-5compat-dev \
                qt6-base-dev \
                qt6-base-private-dev \
                qt6-declarative-dev \
                qt6-multimedia-dev \
                qt6-shadertools-dev \
                qt6-svg-dev \
                qt6-tools-dev \
                qt6-webchannel-dev \
                qt6-webengine-dev \
                rpm \
                unzip \
                zip
        ## GCC Install code below - currently not used but retained for potential future use
        # $SUDO apt install software-properties-common
        # $SUDO add-apt-repository -y ppa:ubuntu-toolchain-r/test
        # $SUDO apt-get update && apt-get upgrade -y
        # $SUDO apt-get install -y gcc-${GCC_VERSION} g++-${GCC_VERSION}
        # $SUDO update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${GCC_VERSION} 100 --slave /usr/bin/g++ g++ /usr/bin/g++-${GCC_VERSION}
        
        # --- Build OpenImageIO from source for Ubuntu ---
        if [ ! -d "/usr/local/include/OpenImageIO" ]; then
            echo "--- Building OpenImageIO from source ---"
            git clone --branch v2.5.9.0 --depth 1 https://github.com/AcademySoftwareFoundation/OpenImageIO.git /tmp/OIIO
            cmake -B /tmp/OIIO/build -S /tmp/OIIO -DCMAKE_BUILD_TYPE=Release -DOIIO_BUILD_TESTS=OFF -DOIIO_BUILD_TOOLS=ON -DUSE_PYTHON=OFF -DOpenColorIO_DIR=/usr/share/cmake
            cmake --build /tmp/OIIO/build -j $(nproc)
            $SUDO cmake --install /tmp/OIIO/build
            rm -rf /tmp/OIIO
        fi

        # --- Build openjph from source for Ubuntu (missing on amd64) ---
        if [ ! -d "/usr/local/include/openjph" ]; then
            echo "--- Building openjph from source ---"
            git clone https://github.com/aous72/OpenJPH.git /tmp/OpenJPH
            cmake -B /tmp/OpenJPH/build -S /tmp/OpenJPH -DCMAKE_BUILD_TYPE=Release
            cmake --build /tmp/OpenJPH/build -j $(nproc)
            $SUDO cmake --install /tmp/OpenJPH/build
            rm -rf /tmp/OpenJPH
        fi

        # Fix Ubuntu 24.04 broken OpenColorIO CMake target
        if [ -f "/usr/share/cmake/OpenColorIOTargets.cmake" ]; then
            $SUDO sed -i 's|\${_IMPORT_PREFIX}/include|/usr/include|g' /usr/share/cmake/OpenColorIOTargets.cmake
        fi
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
    uv venv "${VENV_DIR}" --python ${PYTHON_VERSION}
fi
source "${VENV_DIR}/bin/activate"
uv pip install -r "${PROJECT_ROOT}/requirements.txt"

if [ -d ".git" ]; then
    git config --global --add safe.directory '*'
fi

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

# vcpkg fallback toolchain injection for missing Linux system dependencies
if [ -f "${PROJECT_ROOT}/vcpkg/scripts/buildsystems/vcpkg.cmake" ]; then
    echo "Injecting vcpkg toolchain for system dependency fallbacks..."
    CMAKE_ARGS+=("-DCMAKE_TOOLCHAIN_FILE=${PROJECT_ROOT}/vcpkg/scripts/buildsystems/vcpkg.cmake" "-DVCPKG_BUILD_TYPE=release")
fi

# On Ubuntu, OpenColorIO is installed to /usr/share/cmake, so we manually point it out
if command -v apt-get >/dev/null 2>&1; then
    CMAKE_ARGS+=("-DOpenColorIO_DIR=/usr/share/cmake")
fi

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
