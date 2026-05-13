# Windows Rapid Build Path

This document describes the optimized "Rapid Build" path for UTV on Windows. This path is used in CI and is the primary, autonomous entry point for local development.

## The One-Stop Build Shop

The `build.ps1` script at the root of the repository is designed to be fully self-bootstrapping. On a bare Windows machine, running this script will:

1. **Install Visual Studio 2022**: Automatically detects if VS 2022 with the "C++ Desktop" workload is missing and installs it via Chocolatey.
2. **Install Build Tools**: Automatically installs Chocolatey (if missing) and uses it to install `jom`, `winflexbison3`, `nasm`, `patch`, and `vswhere`.
3. **Install Dependencies**: Automatically downloads and installs the latest **OpenUTVDeps MSI** from GitHub.
4. **Install Qt**: Automatically installs **Qt 6.11.0** (with all required modules) to `C:\Qt` using `aqtinstall`.
5. **Configure & Build**: Automatically syncs Python dependencies, configures CMake, and builds the project.

## Usage

Open a PowerShell terminal as **Administrator** (required for VS, MSI, and Tool installation) and run:

```powershell
.\build.ps1
```

### Options

* `-Debug`: Build in Debug mode.
* `-Clean`: Wipe the `_build` directory before starting.
* `-Install`: Install the resulting binaries to `_install`.
* `-Package`: Create an NSIS installer.
* `-SkipInstall`: Skip the automatic prerequisite check/installation phase.

## Prerequisites

The only hard prerequisite is **Internet Access** to download the various components:

* Visual Studio Build Tools (~1-2GB)
* OpenUTVDeps MSI (~300MB)
* Qt 6.11.0 (~2GB)

## Technical Details

* **Bundled Python**: The script uses the Python 3.12 environment bundled inside the `OpenUTVDeps` MSI. This ensures your local environment perfectly matches the CI environment.
* **Automatic Qt**: Qt is installed using the `aqt` tool. It includes modules like `qtwebengine`, `qtmultimedia`, and `qtquick3d`.
* **Sccache**: The script will automatically detect and use `sccache` if it is present in your `PATH` to accelerate build times.
