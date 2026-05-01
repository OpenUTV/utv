<#
.SYNOPSIS
UTV Build Script for Windows.
Matches CI/CD execution for local development.
Copyright (C) 2026 Makai Systems. All Rights Reserved.

.DESCRIPTION
This script builds UTV on Windows. It can optionally install dependencies using winget,
and package the output into an NSIS installer using CPack.

.PARAMETER Debug
Build in Debug mode.

.PARAMETER Release
Build in Release mode (default).

.PARAMETER Clean
Remove build directory before building.

.PARAMETER Install
Install the build to the _install directory.

.PARAMETER Package
Generate native installers (NSIS/ZIP) via CPack.

.PARAMETER InstallDeps
Install core system build dependencies via winget.
#>
param(
    [switch]$Debug,
    [switch]$Release,
    [switch]$Clean,
    [switch]$Install,
    [switch]$Package,
    [switch]$InstallDeps
)

$ErrorActionPreference = "Stop"
$BuildType = "Release"
if ($Debug) { $BuildType = "Debug" }

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BuildDir = Join-Path $ProjectRoot "_build"
$InstallDir = Join-Path $ProjectRoot "_install"
$VenvDir = Join-Path $ProjectRoot ".venv"

Write-Host "=== UTV Build Script ===" -ForegroundColor Cyan
Write-Host "Build Type: $BuildType"

if ($Clean) {
    Write-Host "Cleaning build and environment directories..." -ForegroundColor Yellow
    if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
    if (Test-Path $VenvDir) { Remove-Item -Recurse -Force $VenvDir }
}

if ($InstallDeps) {
    Write-Host "--- Installing System Dependencies (winget) ---" -ForegroundColor Cyan
    $packages = @(
        "Kitware.CMake",
        "Ninja-build.Ninja",
        "Python.Python.3.14",
        "Microsoft.VisualStudio.2022.BuildTools"
    )
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        foreach ($pkg in $packages) {
            Write-Host "Checking/Installing $pkg..."
            winget install --id $pkg --exact --accept-source-agreements --accept-package-agreements --silent | Out-Null
        }
    } else {
        Write-Host "WARNING: winget not found. Skipping system dependency installation. Please ensure CMake, Ninja, and Visual Studio are installed." -ForegroundColor Yellow
    }

    Write-Host "--- Bootstrapping vcpkg ---" -ForegroundColor Cyan
    $VcpkgDir = Join-Path $ProjectRoot "vcpkg"
    if (-not (Test-Path $VcpkgDir)) {
        Write-Host "Cloning vcpkg..."
        & git clone https://github.com/microsoft/vcpkg.git $VcpkgDir
        & "$VcpkgDir\bootstrap-vcpkg.bat" -disableMetrics
    }
    
    $vcpkgDeps = @(
        "openexr", "boost", "opencolorio", "ffmpeg", "libraw", "tiff", 
        "libpng", "openimageio", "openjpeg", "yaml-cpp", "spdlog"
    )
    
    # Optimize build times by only building Release variants
    $env:VCPKG_BUILD_TYPE = "release"
    
    foreach ($dep in $vcpkgDeps) {
        Write-Host "Installing vcpkg dependency: $dep (Release only)"
        & "$VcpkgDir\vcpkg.exe" install "$dep`:x64-windows"
    }
}

# 1. Setup Python Environment
Write-Host "--- Setting up Python Environment ---" -ForegroundColor Cyan
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "uv not found. Installing astral uv..."
    Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -OutFile "install_uv.ps1"
    & .\install_uv.ps1
    Remove-Item "install_uv.ps1"
    $env:PATH = "$HOME\.cargo\bin;$env:PATH"
}

if (-not (Test-Path $VenvDir)) {
    & uv venv $VenvDir --python 3.14
}
$env:VIRTUAL_ENV = $VenvDir
$env:PATH = "$VenvDir\Scripts;$env:PATH"
& uv pip install -r "$ProjectRoot\requirements.txt"

# 2. Locate Qt6
Write-Host "--- Locating Qt6 ---" -ForegroundColor Cyan
if (-not $env:QT_HOME) {
    $qtPaths = @("C:\Qt\6.*\msvc2019_64", "C:\Qt\6.*\msvc2022_64")
    foreach ($p in $qtPaths) {
        $found = Get-Item -Path $p -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($found) {
            $env:QT_HOME = $found.FullName
            break
        }
    }
}

if (-not $env:QT_HOME) {
    Write-Error "Could not find required Qt 6 installation. Please set QT_HOME."
    exit 1
}
Write-Host "Using QT_HOME=$env:QT_HOME"

# 3. Configure CMake
Write-Host "--- Configuring CMake ---" -ForegroundColor Cyan
$CmakeArgs = @(
    "-B", $BuildDir,
    "-G", "Visual Studio 17 2022",
    "-A", "x64",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DRV_DEPS_QT_LOCATION=$env:QT_HOME",
    "-DRV_VFX_PLATFORM=CY2026",
    "-DRV_USE_SYSTEM_DEPS=ON",
    "-DVCPKG_BUILD_TYPE=release"
)

$VcpkgDir = Join-Path $ProjectRoot "vcpkg"
if (Test-Path "$VcpkgDir\scripts\buildsystems\vcpkg.cmake") {
    $CmakeArgs += "-DCMAKE_TOOLCHAIN_FILE=$VcpkgDir\scripts\buildsystems\vcpkg.cmake"
}

& cmake $CmakeArgs

# 4. Build
Write-Host "--- Building UTV ---" -ForegroundColor Cyan
$Parallelism = [System.Environment]::ProcessorCount

Write-Host "Building dependencies target..."
& cmake --build $BuildDir --config $BuildType --parallel $Parallelism --target dependencies

Write-Host "Building main_executable target..."
& cmake --build $BuildDir --config $BuildType --parallel $Parallelism --target main_executable

# 5. Install / Package
if ($Install) {
    Write-Host "--- Installing UTV ---" -ForegroundColor Cyan
    & cmake --install $BuildDir --prefix $InstallDir --config $BuildType
}

if ($Package) {
    Write-Host "--- Packaging UTV ---" -ForegroundColor Cyan
    Set-Location $BuildDir
    & cpack -G NSIS -C $BuildType
    Set-Location $ProjectRoot
}

Write-Host "=== Build Complete ===" -ForegroundColor Green
if ($Install) { Write-Host "Installed to: $InstallDir" }
Write-Host "Executable is at: $BuildDir\stage\app\bin\utv.exe"
