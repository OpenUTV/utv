<#
.SYNOPSIS
    Official OpenUTV Windows Installer and Upgrader.
.DESCRIPTION
    Installs OpenUTV to Program Files (or AppData for non-admin users),
    automatically verifies and installs OpenUTVDeps runtime dependencies,
    configures system PATH, and creates Start Menu and Desktop shortcuts.
.EXAMPLE
    irm https://openutv.com/install.ps1 | iex
    irm https://raw.githubusercontent.com/OpenUTV/utv/main/scripts/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [string]$Version = "latest",
    [string]$DepsVersion = "26.5",
    [string]$InstallDir = "",
    [switch]$SkipDeps = $false,
    [switch]$NoShortcuts = $false,
    [switch]$Uninstall = $false
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RepoOwner = "OpenUTV"
$RepoName = "utv"
$DepsRepoName = "utv-dependencies"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

# 1. Determine Target Installation Directory
if (-not $InstallDir) {
    if ($isAdmin) {
        $InstallDir = "$env:ProgramFiles\OpenUTV"
    } else {
        $InstallDir = "$env:LOCALAPPDATA\Programs\OpenUTV"
    }
}

# ========================================================
# UNINSTALL MODE
# ========================================================
if ($Uninstall) {
    Write-Host "`n=== Uninstalling OpenUTV ===" -ForegroundColor Cyan
    
    # If running from inside the directory being removed, relaunch from %TEMP%
    if ($PSCommandPath -and $PSCommandPath.StartsWith($InstallDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $tempScript = Join-Path $env:TEMP "openutv-uninstall-$PID.ps1"
        Copy-Item -Path $PSCommandPath -Destination $tempScript -Force
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`" -Uninstall -InstallDir `"$InstallDir`"" -Wait
        Remove-Item -Force $tempScript -ErrorAction SilentlyContinue
        return
    }

    # Remove shortcuts
    $shortcutNames = @("OpenUTV.lnk")
    $shortcutLocations = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
        "$env:USERPROFILE\Desktop",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs",
        "C:\Users\Public\Desktop"
    )
    foreach ($loc in $shortcutLocations) {
        foreach ($name in $shortcutNames) {
            $lnk = Join-Path $loc $name
            if (Test-Path $lnk) {
                Remove-Item -Force $lnk -ErrorAction SilentlyContinue
                Write-Host "Removed shortcut: $lnk" -ForegroundColor Gray
            }
        }
    }

    # Remove ARP registry entry
    $regRoots = if ($isAdmin) { @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall") } else { @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall") }
    foreach ($regRoot in $regRoots) {
        $appKey = Join-Path $regRoot "OpenUTV"
        if (Test-Path $appKey) {
            Remove-Item -Recurse -Force $appKey -ErrorAction SilentlyContinue
            Write-Host "Removed Windows Uninstall registry entry." -ForegroundColor Gray
        }
    }

    # Remove from PATH
    $binDir = Join-Path $InstallDir "bin"
    $pathScope = if ($isAdmin) { "Machine" } else { "User" }
    $currentEnvPath = [Environment]::GetEnvironmentVariable("Path", $pathScope)
    if ($currentEnvPath -like "*$binDir*") {
        $paths = $currentEnvPath -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $binDir.TrimEnd('\') }
        [Environment]::SetEnvironmentVariable("Path", ($paths -join ';'), $pathScope)
        Write-Host "Removed $binDir from $pathScope PATH." -ForegroundColor Gray
    }

    # Remove files
    if (Test-Path $InstallDir) {
        Write-Host "Removing application files from $InstallDir..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
    }

    Write-Host "OpenUTV has been uninstalled successfully." -ForegroundColor Green
    return
}

# ========================================================
# INSTALL MODE
# ========================================================
Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "      OpenUTV Windows Installer" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "Target Directory: $InstallDir" -ForegroundColor White
Write-Host "Administrative Privileges: $isAdmin`n" -ForegroundColor White

# Step 1: Check and Install OpenUTVDeps
Write-Host "--- Checking OpenUTV Dependencies (v$DepsVersion) ---" -ForegroundColor Cyan
$depsFound = $false
$detectedDepsPath = ""

if (Test-Path "C:\Program Files\OpenUTVDeps $DepsVersion\bin\OpenImageIO.dll") {
    $depsFound = $true
    $detectedDepsPath = "C:\Program Files\OpenUTVDeps $DepsVersion"
} elseif ($env:OPENUTV_DEPS_ROOT -and (Test-Path "$env:OPENUTV_DEPS_ROOT\bin\OpenImageIO.dll")) {
    $depsFound = $true
    $detectedDepsPath = $env:OPENUTV_DEPS_ROOT
} elseif (Test-Path "C:\Program Files\OpenUTVDeps*\bin\OpenImageIO.dll") {
    $found = Get-Item "C:\Program Files\OpenUTVDeps*\bin\OpenImageIO.dll" | Select-Object -First 1
    $depsFound = $true
    $detectedDepsPath = $found.Directory.Parent.FullName
} else {
    $uninst = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "OpenUTVDeps $DepsVersion*" -or $_.DisplayName -like "OpenUTV Dependencies $DepsVersion*" } |
        Select-Object -First 1
    if ($uninst -and $uninst.InstallLocation -and (Test-Path "$($uninst.InstallLocation)\bin\OpenImageIO.dll")) {
        $depsFound = $true
        $detectedDepsPath = $uninst.InstallLocation.TrimEnd('\')
    }
}

if ($depsFound) {
    Write-Host "OpenUTV dependencies detected at: $detectedDepsPath" -ForegroundColor Green
} elseif (-not $SkipDeps) {
    Write-Host "OpenUTV dependencies not found. Downloading OpenUTVDeps MSI installer..." -ForegroundColor Yellow
    $msiUrl = "https://github.com/$RepoOwner/$DepsRepoName/releases/download/v$DepsVersion/OpenUTVDeps-$DepsVersion-win64.msi"
    $tempMsi = Join-Path $env:TEMP "OpenUTVDeps-$DepsVersion-win64.msi"

    Write-Host "Downloading $msiUrl..." -ForegroundColor White
    Invoke-WebRequest -Uri $msiUrl -OutFile $tempMsi -UseBasicParsing

    Write-Host "Installing OpenUTVDeps (silent MSI install)..." -ForegroundColor Yellow
    $msiProc = Start-Process msiexec.exe -ArgumentList "/i `"$tempMsi`" /qn /norestart MSIFASTINSTALL=7" -Wait -PassThru
    Remove-Item -Force $tempMsi -ErrorAction SilentlyContinue

    if ($msiProc.ExitCode -ne 0 -and $msiProc.ExitCode -ne 3010) {
        Write-Error "Failed to install OpenUTVDeps MSI. Exit code: $($msiProc.ExitCode)"
        return
    }
    Write-Host "OpenUTVDeps installed successfully!" -ForegroundColor Green
    $detectedDepsPath = "C:\Program Files\OpenUTVDeps $DepsVersion"
} else {
    Write-Host "Skipping OpenUTVDeps download/install (-SkipDeps)." -ForegroundColor Gray
}

# Step 2: Resolve UTV Release Asset
Write-Host "`n--- Downloading OpenUTV ($Version) ---" -ForegroundColor Cyan
if ($Version -eq "latest") {
    $apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
    try {
        $releaseData = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        $Version = $releaseData.tag_name.TrimStart('v')
        $asset = $releaseData.assets | Where-Object { $_.name -match "UTV-.*-windows-x64\.zip" } | Select-Object -First 1
        if ($asset) {
            $zipUrl = $asset.browser_download_url
        }
    } catch {
        Write-Warning "Could not query GitHub API for latest release. Falling back to default release URL."
    }
}

if (-not $zipUrl) {
    if ($Version -eq "latest") { $Version = "2026.9" }
    $zipUrl = "https://github.com/$RepoOwner/$RepoName/releases/download/$Version/UTV-$Version-windows-x64.zip"
}

Write-Host "Release Version: $Version" -ForegroundColor White
Write-Host "Download URL: $zipUrl" -ForegroundColor Gray

$tempZip = Join-Path $env:TEMP "OpenUTV-$Version-windows-x64.zip"
Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing

# Step 3: Extract & Install Application Files
Write-Host "`n--- Installing OpenUTV into $InstallDir ---" -ForegroundColor Cyan
$tempExtract = Join-Path $env:TEMP "OpenUTV-Extract-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $tempExtract | Out-Null
Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
Remove-Item -Force $tempZip -ErrorAction SilentlyContinue

$sourceDir = Join-Path $tempExtract "utv-windows-x64"
if (-not (Test-Path $sourceDir)) {
    $sourceDir = $tempExtract
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
& robocopy $sourceDir $InstallDir /E /MOVE /NDL /NFL /NJH /NJS /nc /ns /np | Out-Null
Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue

$utvExe = Join-Path $InstallDir "bin\utv.exe"
if (-not (Test-Path $utvExe)) {
    Write-Error "Installation failed: utv.exe was not found in $InstallDir\bin"
    return
}

# Step 4: Configure PATH and Environment
Write-Host "`n--- Configuring Environment ---" -ForegroundColor Cyan
$binDir = Join-Path $InstallDir "bin"
$pathScope = if ($isAdmin) { "Machine" } else { "User" }

# Remove orphaned legacy qt.conf if present without plugins\Qt (prevents blocking PySide6 Qt plugin loading)
$legacyQtConf = Join-Path $binDir "qt.conf"
$qtPluginDir = Join-Path $InstallDir "plugins\Qt"
if ((Test-Path $legacyQtConf) -and -not (Test-Path $qtPluginDir)) {
    Remove-Item -Force $legacyQtConf -ErrorAction SilentlyContinue
    Write-Host "Removed legacy qt.conf." -ForegroundColor Gray
}

# Collect paths to add to PATH
$pathsToAdd = @($binDir)

if ($detectedDepsPath -and (Test-Path $detectedDepsPath)) {
    $depsBin = Join-Path $detectedDepsPath "bin"
    $depsPython = Join-Path $detectedDepsPath "tools\python3"
    $depsPySide = Join-Path $detectedDepsPath "tools\python3\Lib\site-packages\PySide6"
    $depsPlugins = Join-Path $depsPySide "plugins"
    $depsPlatforms = Join-Path $depsPlugins "platforms"

    if (Test-Path $depsBin) { $pathsToAdd += $depsBin }
    if (Test-Path $depsPython) { $pathsToAdd += $depsPython }
    if (Test-Path $depsPySide) { $pathsToAdd += $depsPySide }

    # Set persistent OpenUTVDeps environment variables
    [Environment]::SetEnvironmentVariable("OPENUTV_DEPS_ROOT", $detectedDepsPath, $pathScope)
    $env:OPENUTV_DEPS_ROOT = $detectedDepsPath

    if (Test-Path $depsPython) {
        [Environment]::SetEnvironmentVariable("PYTHONHOME", $depsPython, $pathScope)
        $env:PYTHONHOME = $depsPython
    }
    if (Test-Path $depsPlugins) {
        [Environment]::SetEnvironmentVariable("QT_PLUGIN_PATH", $depsPlugins, $pathScope)
        $env:QT_PLUGIN_PATH = $depsPlugins
    }
    if (Test-Path $depsPlatforms) {
        [Environment]::SetEnvironmentVariable("QT_QPA_PLATFORM_PLUGIN_PATH", $depsPlatforms, $pathScope)
        $env:QT_QPA_PLATFORM_PLUGIN_PATH = $depsPlatforms
    }
}

$currentEnvPath = [Environment]::GetEnvironmentVariable("Path", $pathScope)
$currentList = ($currentEnvPath -split ";") | Where-Object { $_ -ne "" }
$newEntries = @()
foreach ($p in $pathsToAdd) {
    if ($currentList -notcontains $p) {
        $newEntries += $p
    }
}

if ($newEntries.Count -gt 0) {
    $newEnvPath = ($newEntries + $currentList) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newEnvPath, $pathScope)
    $env:Path = ($newEntries + ($env:Path -split ";")) -join ";"
    Write-Host "Added $($newEntries.Count) OpenUTV path(s) to $pathScope PATH." -ForegroundColor Green
    foreach ($entry in $newEntries) {
        Write-Host "  + $entry" -ForegroundColor Gray
    }
} else {
    Write-Host "OpenUTV binaries and dependencies already present in $pathScope PATH." -ForegroundColor Gray
}

# Step 5: Create Start Menu and Desktop Shortcuts
if (-not $NoShortcuts) {
    Write-Host "`n--- Creating Shortcuts ---" -ForegroundColor Cyan
    $wsh = New-Object -ComObject WScript.Shell
    
    $startMenuDir = if ($isAdmin) {
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
    } else {
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    }
    $desktopDir = if ($isAdmin) {
        "C:\Users\Public\Desktop"
    } else {
        "$env:USERPROFILE\Desktop"
    }

    $shortcuts = @(
        (Join-Path $startMenuDir "OpenUTV.lnk"),
        (Join-Path $desktopDir "OpenUTV.lnk")
    )

    foreach ($lnkPath in $shortcuts) {
        try {
            $shortcut = $wsh.CreateShortcut($lnkPath)
            $shortcut.TargetPath = $utvExe
            $shortcut.WorkingDirectory = $binDir
            $shortcut.Description = "OpenUTV Sequence Viewer and Media Player"
            $shortcut.IconLocation = "$utvExe,0"
            $shortcut.Save()
            Write-Host "Created shortcut: $lnkPath" -ForegroundColor Green
        } catch {
            Write-Warning "Could not create shortcut at $lnkPath : $_"
        }
    }
}

# Step 6: Register Windows Add/Remove Programs (ARP)
Write-Host "`n--- Registering in Windows Installed Apps ---" -ForegroundColor Cyan
$regRoot = if ($isAdmin) { "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" } else { "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" }
$appRegKey = Join-Path $regRoot "OpenUTV"

try {
    if (-not (Test-Path $appRegKey)) {
        New-Item -ItemType Directory -Force -Path $appRegKey | Out-Null
    }
    Set-ItemProperty -Path $appRegKey -Name "DisplayName" -Value "OpenUTV"
    Set-ItemProperty -Path $appRegKey -Name "DisplayVersion" -Value $Version
    Set-ItemProperty -Path $appRegKey -Name "Publisher" -Value "OpenUTV Contributors"
    Set-ItemProperty -Path $appRegKey -Name "InstallLocation" -Value $InstallDir
    Set-ItemProperty -Path $appRegKey -Name "DisplayIcon" -Value "$utvExe,0"
    Set-ItemProperty -Path $appRegKey -Name "HelpLink" -Value "https://github.com/OpenUTV/utv"
    Set-ItemProperty -Path $appRegKey -Name "URLInfoAbout" -Value "https://openutv.com"
    $uninstCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\scripts\install.ps1`" -Uninstall"
    Set-ItemProperty -Path $appRegKey -Name "UninstallString" -Value $uninstCmd
    Set-ItemProperty -Path $appRegKey -Name "QuietUninstallString" -Value $uninstCmd
    
    # Save a copy of the installer inside the installation dir for uninstall/updates
    $scriptsDir = Join-Path $InstallDir "scripts"
    New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
    $localScript = Join-Path $scriptsDir "install.ps1"
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        Copy-Item -Path $PSCommandPath -Destination $localScript -Force -ErrorAction SilentlyContinue
    } else {
        $scriptUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main/scripts/install.ps1"
        try {
            Invoke-WebRequest -Uri $scriptUrl -OutFile $localScript -UseBasicParsing
        } catch {
            # Non-critical fallback
        }
    }

    Write-Host "Registered OpenUTV in Windows Add/Remove Programs." -ForegroundColor Green
} catch {
    Write-Warning "Could not write to Windows Uninstall registry: $_"
}

Write-Host "`n===============================================" -ForegroundColor Green
Write-Host "  OpenUTV $Version installed successfully!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host "You can run OpenUTV from:" -ForegroundColor White
Write-Host "  1. Start Menu: 'OpenUTV'" -ForegroundColor Cyan
Write-Host "  2. Terminal:   utv" -ForegroundColor Cyan
Write-Host "  3. Binary:     $utvExe`n" -ForegroundColor White
