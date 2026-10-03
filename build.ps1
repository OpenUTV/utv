<#
.SYNOPSIS
UTV Build Script for Windows.
Autonomous one-stop-shop for local development.
Copyright (C) 2026 Makai Systems. All Rights Reserved.

.DESCRIPTION
This script builds UTV on Windows. It automatically detects and installs all
missing prerequisites (OpenUTVDeps MSI, Qt 6.11.2, Build Tools) to provide
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

# --- 2. Visual Studio 2022 or newer (CI builds with 2022) ---
Write-Host "`n--- Checking Visual Studio ---" -ForegroundColor Cyan
$vsInstalled = $false
# The Visual Studio Installer ships vswhere; Chocolatey's (step 3) may not be installed yet.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { $vswhere = (Get-Command vswhere -ErrorAction SilentlyContinue).Source }
if ($vswhere) {
    $vsPath = & $vswhere -latest -version "[17.0,)" -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath
    if ($vsPath) { 
        $vsInstalled = $true 
        Write-Host "Found Visual Studio at $vsPath" -ForegroundColor Gray
    }
}

# CMake generator for the Visual Studio found: 2026 (18.x) or 2022 (17.x).
$CmakeGenerator = "Visual Studio 17 2022"
if ($vsInstalled) {
    $vsMajor = ((& $vswhere -latest -version "[17.0,)" -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationVersion) -split '\.')[0]
    if ($vsMajor -eq "18") { $CmakeGenerator = "Visual Studio 18 2026" }
    # Use the CMake that ships with Visual Studio when none is on PATH.
    $vsCmake = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue) -and (Test-Path "$vsCmake\cmake.exe")) {
        $env:PATH = "$vsCmake;$env:PATH"
    }
}

if (-not $vsInstalled -and -not $SkipBootstrapping) {
    Write-Host "Visual Studio with the C++ workload not found. Installing Visual Studio 2022 Build Tools via Chocolatey..." -ForegroundColor Yellow
    # Install Build Tools and the Native Desktop (C++) workload
    & choco install visualstudio2022buildtools --yes --no-progress
    & choco install visualstudio2022-workload-nativedesktop --yes --no-progress
}

# --- 3. System Build Tools ---
Write-Host "`n--- Checking Build Tools ---" -ForegroundColor Cyan
# Chocolatey package -> command it provides
$requiredTools = [ordered]@{
    "jom"           = "jom"
    "winflexbison3" = "win_bison"
    "nasm"          = "nasm"
    "patch"         = "patch"
    "vswhere"       = "vswhere"
    "pkgconfiglite" = "pkg-config"
}

# Chocolatey's nasm package installs to Program Files without adding it to PATH.
$nasmDir = Join-Path $env:ProgramFiles "NASM"
if ((Test-Path "$nasmDir\nasm.exe") -and -not (Get-Command nasm -ErrorAction SilentlyContinue)) {
    $env:PATH = "$nasmDir;$env:PATH"
}

$missingTools = @($requiredTools.Keys | Where-Object { -not (Get-Command $requiredTools[$_] -ErrorAction SilentlyContinue) })

if ($missingTools.Count -gt 0 -and -not $SkipBootstrapping) {
    Write-Host "Missing tools: $($missingTools -join ', '). Installing via Chocolatey..." -ForegroundColor Yellow
    foreach ($tool in $missingTools) {
        & choco install $tool --yes --no-progress
    }
    $env:PATH += ";C:\ProgramData\chocolatey\bin"
    if (Test-Path "$nasmDir\nasm.exe") { $env:PATH = "$nasmDir;$env:PATH" }
}

# --- 4. OpenUTVDeps MSI ---
Write-Host "`n--- Checking OpenUTVDeps MSI ---" -ForegroundColor Cyan
# The release the build is pinned to (cmake/openutv-deps-version.txt): the launchers only accept that one.
$DepsVersion = (Get-Content (Join-Path $ProjectRoot "cmake\openutv-deps-version.txt") -TotalCount 1).Trim()
$DepsDir = Get-Item -Path "C:\Program Files\OpenUTVDeps $DepsVersion" -ErrorAction SilentlyContinue
if (-not $DepsDir -and -not $SkipBootstrapping) {
    Write-Host "OpenUTVDeps $DepsVersion not found. Downloading it..." -ForegroundColor Yellow
    $MsiPath = Join-Path $env:TEMP "OpenUTVDeps-$DepsVersion-win64.msi"
    Invoke-WebRequest -Uri "https://github.com/OpenUTV/utv-dependencies/releases/download/v$DepsVersion/OpenUTVDeps-$DepsVersion-win64.msi" -OutFile $MsiPath
    Write-Host "Installing MSI (this may take a minute)..."
    $msiProcess = Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /qn /passive" -Wait -PassThru
    if ($msiProcess.ExitCode -eq 0 -or $msiProcess.ExitCode -eq 3010) {
        Write-Host "MSI installed successfully." -ForegroundColor Green
        $DepsDir = Get-Item -Path "C:\Program Files\OpenUTVDeps $DepsVersion" -ErrorAction SilentlyContinue
    }
    else {
        Write-Error "MSI installation failed with exit code $($msiProcess.ExitCode)"
    }
}
if (-not $DepsDir) {
    Write-Error "OpenUTVDeps $DepsVersion is required but not found. Install OpenUTVDeps-$DepsVersion-win64.msi."
    exit 1
}
Write-Host "Using OpenUTVDeps at $($DepsDir.FullName)" -ForegroundColor Gray

# Python: pythonLocation when CI (or an earlier run of this script in the same shell) set it, else the OpenUTVDeps one.
if ($env:pythonLocation -and (Test-Path "$env:pythonLocation\python.exe")) {
    $PythonPath = $env:pythonLocation
}
else {
    $PythonPath = Join-Path $DepsDir.FullName "tools\python3"
    if (-not (Test-Path "$PythonPath\python.exe")) {
        $PythonPath = Join-Path $DepsDir.FullName "installed\x64-windows\tools\python3"
    }
}
Write-Host "Using Python at $PythonPath" -ForegroundColor Gray

# Sync pythonLocation for CMake
$env:pythonLocation = $PythonPath
$env:OPENUTV_DEPS_ROOT = $DepsDir.FullName
$DepsSlash = $DepsDir.FullName.Replace('\', '/')
$env:CMAKE_PREFIX_PATH = "$DepsSlash;$env:CMAKE_PREFIX_PATH"
$env:ZLIB_ROOT = $DepsSlash
$env:PKG_CONFIG_PATH = "$DepsSlash/lib/pkgconfig;$env:PKG_CONFIG_PATH"
$env:CMAKE_ARGS = "-DCMAKE_PREFIX_PATH=$DepsSlash -DZLIB_ROOT=$DepsSlash"
$env:INCLUDE = "$($DepsDir.FullName)\include;$env:INCLUDE"
$env:LIB = "$($DepsDir.FullName)\lib;$env:LIB"

# The build runs staged tools (format caches, package install) that load the OpenUTVDeps DLLs. The MSI does not put
# them on the system PATH, so put them on this process's PATH, as the launchers do for installed programs.
$DepsPySide = Join-Path $DepsDir.FullName "tools\python3\Lib\site-packages\PySide6"
$env:PATH = "$($DepsDir.FullName)\bin;$DepsPySide;$env:PATH"

# Ensure Python C-extension modules (.pyd files like _socket.pyd) exist
$DllsPath = Join-Path $PythonPath "DLLs"
if (-not (Test-Path "$PythonPath\_socket.pyd") -and -not (Test-Path "$DllsPath\_socket.pyd")) {
    Write-Host "Fetching Python 3.14.7 standard extension modules..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $DllsPath | Out-Null
    $PyEmbedZip = Join-Path $env:TEMP "pyembed.zip"
    $PyEmbedDir = Join-Path $env:TEMP "pyembed"
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.14.7/python-3.14.7-embed-amd64.zip" -OutFile $PyEmbedZip
    Expand-Archive -Path $PyEmbedZip -DestinationPath $PyEmbedDir -Force
    $BinPath = Join-Path $DepsDir.FullName "bin"
    Get-ChildItem -Path $PyEmbedDir | Where-Object { ($_.Extension -eq ".pyd" -or $_.Extension -eq ".dll") -and $_.Name -notin @("python.exe", "pythonw.exe", "python314.dll") } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $DllsPath -Force
        Copy-Item -Path $_.FullName -Destination $PythonPath -Force
        if (Test-Path $BinPath) {
            Copy-Item -Path $_.FullName -Destination $BinPath -Force
        }
    }
}

# Bootstrap pip into the bundled Python if missing
$hasPip = & "$PythonPath\python.exe" -c "import importlib.util; print('OK' if importlib.util.find_spec('pip') else 'MISSING')"
if ($hasPip -ne "OK") {
    Write-Host "Bootstrapping pip into bundled Python..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "$env:TEMP\get-pip.py"
    & "$PythonPath\python.exe" "$env:TEMP\get-pip.py" --no-warn-script-location
}

# Ensure PySide6 is present in bundled Python
$hasPySide = & "$PythonPath\python.exe" -c "import importlib.util; print('OK' if importlib.util.find_spec('PySide6') else 'MISSING')" 2>$null
if ($hasPySide -ne "OK") {
    Write-Host "Installing PySide6 into bundled Python..." -ForegroundColor Yellow
    & "$PythonPath\python.exe" -m pip install "PySide6==6.11.2" --no-warn-script-location
}

# --- 5. Qt 6.11.2 ---
Write-Host "`n--- Checking Qt 6.11.2 ---" -ForegroundColor Cyan
# Honor existing QT_HOME if set (e.g. by CI's install-qt-action)
if ($env:QT_HOME -and (Test-Path $env:QT_HOME)) {
    $QtPath = $env:QT_HOME
    Write-Host "Using existing Qt from environment: $QtPath" -ForegroundColor Gray
}
else {
    $QtVersion = "6.11.2"
    $QtTargetDir = "C:\Qt"
    $QtPath = Join-Path $QtTargetDir "$QtVersion\msvc2022_64"

    if (-not (Test-Path $QtPath) -and -not $SkipBootstrapping) {
        Write-Host "Qt $QtVersion not found at $QtPath. Installing via aqtinstall..." -ForegroundColor Yellow
        if (-not (Test-Path $QtTargetDir)) { New-Item -ItemType Directory -Path $QtTargetDir }
        
        # aqtinstall from master, as CI's install-qt-action uses: the 3.3.0 release cannot find Qt 6.11 in Qt's
        # repository, which now has a directory per architecture (qt6_6112/qt6_6112_msvc2022_64).
        # --python, not --system: --system takes the first Python on PATH, which can be the user's own.
        & "$PythonPath\python.exe" -m pip install --upgrade uv
        & "$PythonPath\Scripts\uv.exe" pip install --python "$PythonPath\python.exe" "aqtinstall @ git+https://github.com/miurahr/aqtinstall.git@master"

        # The modules and archives CI installs (.github/actions/build-windows/action.yml, windows_qt6_modules/archives).
        Write-Host "Installing Qt $QtVersion (this will take a while)..."
        & "$PythonPath\python.exe" -m aqt install-qt windows desktop $QtVersion win64_msvc2022_64 --outputdir $QtTargetDir `
            --modules qtimageformats qtmultimedia qtpdf qtpositioning qtshadertools qtwebchannel qtwebengine `
            --archives d3dcompiler_47 opengl32sw qtbase qtdeclarative qtsvg qttools qttranslations
    }
}

# Sync PATH for build phase
$env:PATH = "$PythonPath;$PythonPath\Scripts;C:\ProgramData\chocolatey\bin;$env:PATH"

if (-not (Test-Path $QtPath)) {
    Write-Error "Qt 6.11.2 was not found. In CI, ensure the install-qt-action ran successfully. Locally, do not use -SkipBootstrapping."
    exit 1
}
$env:QT_HOME = $QtPath
Write-Host "Using QT_HOME=$env:QT_HOME"

# --- 6. Python Dependencies ---
Write-Host "`n--- Syncing Python Dependencies ---" -ForegroundColor Cyan
& "$PythonPath\python.exe" -m pip install --upgrade uv
& "$PythonPath\Scripts\uv.exe" pip install --python "$PythonPath\python.exe" -r "$ProjectRoot\requirements.txt"

# Stop with the exit code of a failed native step (cmake, cpack) instead of continuing.
function Assert-LastExitCode([string]$step) {
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n$step failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

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
    "-G", $CmakeGenerator,
    "-A", "x64",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DRV_DEPS_WIN_PERL_ROOT=c:/Strawberry/perl/bin",
    "-DCMAKE_PREFIX_PATH=$PrefixPaths",
    "-DPython3_ROOT_DIR=$PythonPath",
    "-DRV_VFX_PLATFORM=CY2026",
    "-DRV_USE_SYSTEM_DEPS=ON"
)

if ($env:VULKAN_SDK) {
    $VulkanSlash = $env:VULKAN_SDK.Replace('\', '/')
    $CmakeArgs += "-DVulkan_ROOT=$VulkanSlash"
} else {
    $VulkanDir = Get-ChildItem -Path "C:\VulkanSDK" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($VulkanDir) {
        $VulkanSlash = $VulkanDir.FullName.Replace('\', '/')
        $CmakeArgs += "-DVulkan_ROOT=$VulkanSlash"
    }
}

if (Get-Command sccache -ErrorAction SilentlyContinue) {
    Write-Host "Enabling sccache..."
    $CmakeArgs += "-DCMAKE_C_COMPILER_LAUNCHER=sccache"
    $CmakeArgs += "-DCMAKE_CXX_COMPILER_LAUNCHER=sccache"
}

& cmake $CmakeArgs
Assert-LastExitCode "CMake configure"

# --- 8. Build ---
Write-Host "`n--- Building UTV ---" -ForegroundColor Cyan
$Parallelism = [System.Environment]::ProcessorCount

Write-Host "Building dependencies target..."
& cmake --build $BuildDir --config $BuildType --parallel $Parallelism --target dependencies
Assert-LastExitCode "Building the dependencies target"

Write-Host "Building main_executable target..."
& cmake --build $BuildDir --config $BuildType --parallel $Parallelism --target main_executable
Assert-LastExitCode "Building the main_executable target"

# --- 9. Install / Package ---
if ($Install) {
    Write-Host "`n--- Installing UTV ---" -ForegroundColor Cyan
    & cmake --install $BuildDir --prefix $InstallDir --config $BuildType
    Assert-LastExitCode "cmake --install"
}

if ($Package) {
    Write-Host "`n--- Packaging UTV ---" -ForegroundColor Cyan
    Set-Location $BuildDir
    & cpack -G NSIS -C $BuildType
    Assert-LastExitCode "cpack"
    Set-Location $ProjectRoot
}

Write-Host "`n=== Build Complete ===" -ForegroundColor Green
if ($Install) { Write-Host "Installed to: $InstallDir" }
Write-Host "Executable is at: $BuildDir\stage\app\bin\utv.exe"
