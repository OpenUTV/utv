<#
.SYNOPSIS
UTV Build Script for Windows.
Autonomous one-stop-shop for local development.
Copyright (C) 2026 Makai Systems. All Rights Reserved.

.DESCRIPTION
This script builds UTV on Windows. It automatically detects and installs all
missing prerequisites (OpenUTVDeps MSI, Qt 6.11.0, Build Tools) to provide
a seamless "one-command" build experience.

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

.PARAMETER SkipBootstrapping
Skip the automatic installation of missing dependencies (recommended for CI).
#>
param(
    [switch]$Debug,
    [switch]$Release,
    [switch]$Clean,
    [switch]$Install,
    [switch]$Package,
    [switch]$SkipBootstrapping
)

$ErrorActionPreference = "Stop"
$BuildType = "Release"
if ($Debug) { $BuildType = "Debug" }

# Detect CI environment
$IsCI = $env:GITHUB_ACTIONS -eq "true"
if ($IsCI) {
    Write-Host "Detected GitHub Actions environment. Auto-bootstrapping disabled by default." -ForegroundColor Gray
    $SkipBootstrapping = $true
}

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BuildDir = Join-Path $ProjectRoot "_build"
$InstallDir = Join-Path $ProjectRoot "_install"

Write-Host "=== UTV One-Stop Build Script ===" -ForegroundColor Cyan
Write-Host "Build Type: $BuildType"

if ($Clean) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
}

# --- 1. Chocolatey (Base Provider) ---
if (-not (Get-Command choco -ErrorAction SilentlyContinue) -and -not $SkipBootstrapping) {
    Write-Host "`n--- Installing Chocolatey ---" -ForegroundColor Cyan
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
}

# --- 2. Visual Studio 2022 ---
Write-Host "`n--- Checking Visual Studio 2022 ---" -ForegroundColor Cyan
$vsInstalled = $false
if (Get-Command vswhere -ErrorAction SilentlyContinue) {
    $vsPath = & vswhere -version "[17.0,18.0)" -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath
    if ($vsPath) { 
        $vsInstalled = $true 
        Write-Host "Found Visual Studio at $vsPath" -ForegroundColor Gray
    }
}

if (-not $vsInstalled -and -not $SkipBootstrapping) {
    Write-Host "Visual Studio 2022 with C++ workload not found. Installing via Chocolatey..." -ForegroundColor Yellow
    # Install Build Tools and the Native Desktop (C++) workload
    & choco install visualstudio2022buildtools --yes --no-progress
    & choco install visualstudio2022-workload-nativedesktop --yes --no-progress
}

# --- 3. System Build Tools ---
Write-Host "`n--- Checking Build Tools ---" -ForegroundColor Cyan
$requiredTools = @("jom", "winflexbison3", "nasm", "patch", "vswhere")
$missingTools = @()

foreach ($tool in $requiredTools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        $missingTools += $tool
    }
}

if ($missingTools.Count -gt 0 -and -not $SkipBootstrapping) {
    Write-Host "Missing tools: $($missingTools -join ', '). Installing via Chocolatey..." -ForegroundColor Yellow
    foreach ($tool in $missingTools) {
        & choco install $tool --yes --no-progress
    }
    $env:PATH += ";C:\ProgramData\chocolatey\bin"
}

# --- 4. OpenUTVDeps MSI ---
Write-Host "`n--- Checking OpenUTVDeps MSI ---" -ForegroundColor Cyan
# Honor existing pythonLocation if set in CI
if ($env:pythonLocation -and (Test-Path "$env:pythonLocation\python.exe")) {
    Write-Host "Using existing Python from environment: $env:pythonLocation" -ForegroundColor Gray
    $PythonPath = $env:pythonLocation
}
else {
    $DepsDir = Get-ChildItem -Path "C:\Program Files\OpenUTVDeps *" | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $DepsDir -and -not $SkipBootstrapping) {
        Write-Host "OpenUTVDeps MSI not found. Downloading latest release..." -ForegroundColor Yellow
        $ReleaseUrl = "https://api.github.com/repos/openutv/utv-dependencies/releases/latest"
        $ReleaseData = Invoke-RestMethod -Uri $ReleaseUrl
        $Asset = $ReleaseData.assets | Where-Object { $_.name -like "*.msi" } | Select-Object -First 1
        if ($Asset) {
            $MsiPath = Join-Path $env:TEMP "OpenUTVDeps.msi"
            Write-Host "Downloading $($Asset.name)..."
            Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $MsiPath
            Write-Host "Installing MSI (this may take a minute)..."
            $msiProcess = Start-Process msiexec.exe -ArgumentList "/i $MsiPath /qn /passive" -Wait -PassThru
            if ($msiProcess.ExitCode -eq 0 -or $msiProcess.ExitCode -eq 3010) {
                Write-Host "MSI installed successfully." -ForegroundColor Green
                $DepsDir = Get-ChildItem -Path "C:\Program Files\OpenUTVDeps *" | Sort-Object Name -Descending | Select-Object -First 1
            }
            else {
                Write-Error "MSI installation failed with exit code $($msiProcess.ExitCode)"
            }
        }
    }

    if (-not $DepsDir) {
        Write-Error "OpenUTVDeps MSI is required but not found. Please install it manually."
        exit 1
    }
    $PythonPath = Join-Path $DepsDir.FullName "tools\python3"
    if (-not (Test-Path "$PythonPath\python.exe")) {
        $PythonPath = Join-Path $DepsDir.FullName "installed\x64-windows\tools\python3"
    }
    if (-not (Test-Path "$PythonPath\python.exe")) {
        $PythonPath = Join-Path $DepsDir.FullName "bin"
    }
}

# Sync pythonLocation for CMake
$env:pythonLocation = $PythonPath
$env:OPENUTV_DEPS_ROOT = $DepsDir.FullName

# Bootstrap pip into the bundled Python if missing
$hasPip = & "$PythonPath\python.exe" -c "import importlib.util; print('OK' if importlib.util.find_spec('pip') else 'MISSING')"
if ($hasPip -ne "OK") {
    Write-Host "Bootstrapping pip into bundled Python..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "$env:TEMP\get-pip.py"
    & "$PythonPath\python.exe" "$env:TEMP\get-pip.py" --no-warn-script-location
}

# --- 5. Qt 6.11.0 ---
Write-Host "`n--- Checking Qt 6.11.0 ---" -ForegroundColor Cyan
# Honor existing QT_HOME if set (e.g. by CI's install-qt-action)
if ($env:QT_HOME -and (Test-Path $env:QT_HOME)) {
    $QtPath = $env:QT_HOME
    Write-Host "Using existing Qt from environment: $QtPath" -ForegroundColor Gray
}
else {
    $QtVersion = "6.11.0"
    $QtTargetDir = "C:\Qt"
    $QtPath = Join-Path $QtTargetDir "$QtVersion\msvc2022_64"

    if (-not (Test-Path $QtPath) -and -not $SkipBootstrapping) {
        Write-Host "Qt $QtVersion not found at $QtPath. Installing via aqtinstall..." -ForegroundColor Yellow
        if (-not (Test-Path $QtTargetDir)) { New-Item -ItemType Directory -Path $QtTargetDir }
        
        # Ensure aqtinstall is present in bundled python
        & "$PythonPath\python.exe" -m pip install --upgrade uv
        & "$PythonPath\Scripts\uv.exe" pip install --system aqtinstall
        
        Write-Host "Installing Qt $QtVersion (this will take a while)..."
        & "$PythonPath\Scripts\aqt.exe" install-qt windows desktop $QtVersion win64_msvc2022_64 --outputdir $QtTargetDir --modules qt3d qt5compat qtactiveqt qtcharts qtconnectivity qtdatavis3d qtgrpc qthttpserver qtimageformats qtlanguageserver qtlocation qtlottie qtmultimedia qtnetworkauth qtpdf qtpositioning qtquick3d qtquick3dphysics qtquickeffectmaker qtquicktimeline qtremoteobjects qtscxml qtsensors qtserialbus qtserialport qtshadertools qtspeech qtvirtualkeyboard qtwebchannel qtwebengine qtwebsockets qtwebview
    }
}

# Sync PATH for build phase
$env:PATH = "$PythonPath;$PythonPath\Scripts;C:\ProgramData\chocolatey\bin;$env:PATH"

if (-not (Test-Path $QtPath)) {
    Write-Error "Qt 6.11.0 was not found. In CI, ensure the install-qt-action ran successfully. Locally, do not use -SkipBootstrapping."
    exit 1
}
$env:QT_HOME = $QtPath
Write-Host "Using QT_HOME=$env:QT_HOME"

# --- 6. Python Dependencies ---
Write-Host "`n--- Syncing Python Dependencies ---" -ForegroundColor Cyan
& "$PythonPath\python.exe" -m pip install --upgrade uv
& "$PythonPath\Scripts\uv.exe" pip install --system -r "$ProjectRoot\requirements.txt"

# --- 7. Configure CMake ---
Write-Host "`n--- Configuring CMake ---" -ForegroundColor Cyan
# Add JOM path to PATH explicitly for the configure session
if (Test-Path "C:\ProgramData\chocolatey\lib\jom\tools") {
    $env:PATH = "C:\ProgramData\chocolatey\lib\jom\tools;$env:PATH"
}

$PrefixPaths = $env:QT_HOME
if ($env:OPENUTV_DEPS_ROOT) {
    $PrefixPaths += ";$env:OPENUTV_DEPS_ROOT"
}

$CmakeArgs = @(
    "-B", $BuildDir,
    "-G", "Visual Studio 17 2022",
    "-A", "x64",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DRV_DEPS_WIN_PERL_ROOT=c:/Strawberry/perl/bin",
    "-DCMAKE_PREFIX_PATH=$PrefixPaths",
    "-DPython3_ROOT_DIR=$PythonPath",
    "-DRV_VFX_PLATFORM=CY2026",
    "-DRV_USE_SYSTEM_DEPS=ON"
)

if (Get-Command sccache -ErrorAction SilentlyContinue) {
    Write-Host "Enabling sccache..."
    $CmakeArgs += "-DCMAKE_C_COMPILER_LAUNCHER=sccache"
    $CmakeArgs += "-DCMAKE_CXX_COMPILER_LAUNCHER=sccache"
}

& cmake $CmakeArgs

# --- 8. Build ---
Write-Host "`n--- Building UTV ---" -ForegroundColor Cyan
$Parallelism = [System.Environment]::ProcessorCount

Write-Host "Building dependencies target..."
& cmake --build $BuildDir --config $BuildType --parallel $Parallelism --target dependencies

Write-Host "Building main_executable target..."
& cmake --build $BuildDir --config $BuildType --parallel $Parallelism --target main_executable

# --- 9. Install / Package ---
if ($Install) {
    Write-Host "`n--- Installing UTV ---" -ForegroundColor Cyan
    & cmake --install $BuildDir --prefix $InstallDir --config $BuildType
}

if ($Package) {
    Write-Host "`n--- Packaging UTV ---" -ForegroundColor Cyan
    Set-Location $BuildDir
    & cpack -G NSIS -C $BuildType
    Set-Location $ProjectRoot
}

Write-Host "`n=== Build Complete ===" -ForegroundColor Green
if ($Install) { Write-Host "Installed to: $InstallDir" }
Write-Host "Executable is at: $BuildDir\stage\app\bin\utv.exe"
