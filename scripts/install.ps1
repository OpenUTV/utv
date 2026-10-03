<#
.SYNOPSIS
    Official OpenUTV Windows Installer and Upgrader.
.DESCRIPTION
    Installs OpenUTV to Program Files (or AppData for non-admin users), installs the OpenUTVDeps
    release the package needs, puts <install>\cmd on PATH, creates Start Menu and Desktop shortcuts
    and registers OpenUTV in Installed Apps.

    The release zip also works without this script: extract it anywhere and run bin\utv.exe. The
    launchers find OpenUTVDeps and set the environment for their own process, so the installer sets
    no environment variables besides PATH. <install>\cmd only contains launchers; bin, with the
    DLLs, stays off PATH.
.PARAMETER DepsVersion
    OpenUTVDeps release to install. Default: the one the package names in bin\openutv-deps-version.txt.
.PARAMETER Version
    "latest" (default) installs the latest release. A release tag such as "2026.9" installs that
    release. "dev-build" installs the newest development pre-release built from main.
.PARAMETER ZipPath
    Install from a UTV Windows zip already on disk (for example a CI build artifact) instead of
    downloading a release.
.EXAMPLE
    irm https://openutv.com/install.ps1 | iex
    irm https://raw.githubusercontent.com/OpenUTV/utv/main/scripts/install.ps1 | iex
.EXAMPLE
    # Development pre-release (parameters can't be passed through "irm | iex")
    & ([scriptblock]::Create((irm https://openutv.com/install.ps1))) -Version dev-build
.EXAMPLE
    .\install.ps1 -ZipPath .\UTV-windows-x64.zip
#>
[CmdletBinding()]
param(
    [string]$Version = "latest",
    [string]$DepsVersion = "",
    [string]$InstallDir = "",
    [string]$ZipPath = "",
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

$pathScope = if ($isAdmin) { "Machine" } else { "User" }

function Remove-FromPath([string[]]$dirs, [string]$scope) {
    $current = [Environment]::GetEnvironmentVariable("Path", $scope)
    if (-not $current) { return }
    $trimmed = $dirs | ForEach-Object { $_.TrimEnd('\') }
    $kept = $current -split ';' | Where-Object { $_ -and ($trimmed -notcontains $_.TrimEnd('\')) }
    $new = $kept -join ';'
    if ($new -ne $current) {
        [Environment]::SetEnvironmentVariable("Path", $new, $scope)
        Write-Host "Removed $($dirs -join ', ') from $scope PATH." -ForegroundColor Gray
    }
}

# Earlier installers stored the dependency location and Python/Qt settings in the user or system
# environment. The launchers set them per process now. Only values that point at OpenUTV or
# OpenUTVDeps are removed, never a user's own PYTHONHOME or QT_PLUGIN_PATH. OPENUTV_DEPS_ROOT in
# the system environment belongs to the OpenUTVDeps MSI and is left alone.
function Remove-LegacyEnvironment {
    $scopes = @("User")
    if ($isAdmin) { $scopes += "Machine" }
    foreach ($scope in $scopes) {
        $names = @("UTV_DEPS_ROOT", "UTV_HOME", "OPENUTV_HOME", "PYTHONHOME", "QT_PLUGIN_PATH", "QT_QPA_PLATFORM_PLUGIN_PATH")
        if ($scope -eq "User") { $names += "OPENUTV_DEPS_ROOT" }
        foreach ($name in $names) {
            $value = [Environment]::GetEnvironmentVariable($name, $scope)
            if ($value -and ($value -like "*OpenUTVDeps*" -or $value -like "*\OpenUTV" -or $value -like "*\OpenUTV\*")) {
                [Environment]::SetEnvironmentVariable($name, $null, $scope)
                [Environment]::SetEnvironmentVariable($name, $null, "Process")
                Write-Host "Removed $name from the $scope environment (was $value)." -ForegroundColor Gray
            }
        }
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

    # Remove from PATH (cmd; bin from older installs) and earlier installers' environment variables
    Remove-FromPath @((Join-Path $InstallDir "cmd"), (Join-Path $InstallDir "bin")) $pathScope
    Remove-LegacyEnvironment

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

# Step 1: Resolve UTV Release Asset
#
# The default (no parameters) installs the latest release. The opt-in paths below, -ZipPath and
# -Version dev-build, must not change what the default does.
$zipUrl = $null
$localZip = $null
if ($ZipPath) {
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        Write-Error "-ZipPath: file not found: $ZipPath"
        return
    }
    $localZip = (Resolve-Path -LiteralPath $ZipPath).Path
    if ($Version -eq "latest") { $Version = "local" }
    Write-Host "--- Installing OpenUTV from $localZip ---" -ForegroundColor Cyan
} else {
    Write-Host "--- Downloading OpenUTV ($Version) ---" -ForegroundColor Cyan
}

if (-not $localZip -and $Version -eq "dev-build") {
    # The development pre-release keeps one moving tag, and its asset name does not contain the tag.
    $apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/tags/dev-build"
    try {
        $releaseData = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        $asset = $releaseData.assets | Where-Object { $_.name -match "UTV-.*-windows-x64\.zip" } | Select-Object -First 1
        if ($asset) {
            $zipUrl = $asset.browser_download_url
        }
    } catch {
        Write-Warning "Could not query GitHub API for the dev-build release. Falling back to the default asset URL."
    }
    if (-not $zipUrl) {
        $zipUrl = "https://github.com/$RepoOwner/$RepoName/releases/download/dev-build/UTV-dev-windows-x64.zip"
    }
} elseif (-not $localZip -and $Version -eq "latest") {
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

if (-not $localZip -and -not $zipUrl) {
    if ($Version -eq "latest") { $Version = "2026.9" }
    $zipUrl = "https://github.com/$RepoOwner/$RepoName/releases/download/$Version/UTV-$Version-windows-x64.zip"
}

Write-Host "Release Version: $Version" -ForegroundColor White

$tempZip = Join-Path $env:TEMP "OpenUTV-$Version-windows-x64.zip"
if ($localZip) {
    # Work on a copy: the temporary zip is deleted after extraction.
    Copy-Item -LiteralPath $localZip -Destination $tempZip -Force
} else {
    Write-Host "Download URL: $zipUrl" -ForegroundColor Gray
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
}

# Step 2: Extract
$tempExtract = Join-Path $env:TEMP "OpenUTV-Extract-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $tempExtract | Out-Null
Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
Remove-Item -Force $tempZip -ErrorAction SilentlyContinue

# A CI artifact downloaded from the GitHub web page is a zip that contains the UTV zip.
if ($localZip -and -not (Test-Path (Join-Path $tempExtract "utv-windows-x64"))) {
    $innerZips = @(Get-ChildItem -Path $tempExtract -Filter "*.zip" -File)
    if ($innerZips.Count -eq 1) {
        Expand-Archive -Path $innerZips[0].FullName -DestinationPath $tempExtract -Force
        Remove-Item -Force $innerZips[0].FullName -ErrorAction SilentlyContinue
    }
}

$sourceDir = Join-Path $tempExtract "utv-windows-x64"
if (-not (Test-Path $sourceDir)) {
    $sourceDir = $tempExtract
}
if (-not (Test-Path (Join-Path $sourceDir "bin\utv.exe"))) {
    Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue
    Write-Error "Installation failed: the package has no bin\utv.exe"
    return
}

# Step 3: OpenUTVDeps, the release this package was built against
if (-not $DepsVersion) {
    $versionFile = Join-Path $sourceDir "bin\openutv-deps-version.txt"
    # Packages from before the launcher rework (2026.11 and older) do not name it; they use 26.5.
    $DepsVersion = if (Test-Path $versionFile) { (Get-Content $versionFile -TotalCount 1).Trim() } else { "26.5" }
}
Write-Host "`n--- Checking OpenUTV Dependencies (OpenUTVDeps $DepsVersion) ---" -ForegroundColor Cyan

function Test-DepsRoot([string]$root) {
    return $root -and (Test-Path (Join-Path $root "bin\OpenImageIO.dll")) -and
        (Test-Path (Join-Path $root "tools\python3\Lib\site-packages\PySide6\Qt6Core.dll"))
}

function Format-Version([string]$version) {
    return ($version.Trim() -replace '^v', '') -replace '(\.0)+$', ''
}

$detectedDepsPath = ""
$installedDeps = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Where-Object { ($_.DisplayName -like "OpenUTVDeps*" -or $_.DisplayName -like "OpenUTV Dependencies*") -and $_.InstallLocation }
foreach ($entry in $installedDeps) {
    $root = $entry.InstallLocation.TrimEnd('\')
    if ((Test-DepsRoot $root) -and $entry.DisplayVersion -and ((Format-Version $entry.DisplayVersion) -eq (Format-Version $DepsVersion))) {
        $detectedDepsPath = $root
        break
    }
}
if (-not $detectedDepsPath -and (Test-DepsRoot "$env:ProgramFiles\OpenUTVDeps $DepsVersion")) {
    $detectedDepsPath = "$env:ProgramFiles\OpenUTVDeps $DepsVersion"
}

if ($detectedDepsPath) {
    Write-Host "OpenUTVDeps $DepsVersion found at: $detectedDepsPath" -ForegroundColor Green
} elseif (-not $SkipDeps) {
    Write-Host "OpenUTVDeps $DepsVersion not found. Downloading the OpenUTVDeps MSI installer..." -ForegroundColor Yellow
    $msiUrl = "https://github.com/$RepoOwner/$DepsRepoName/releases/download/v$DepsVersion/OpenUTVDeps-$DepsVersion-win64.msi"
    $tempMsi = Join-Path $env:TEMP "OpenUTVDeps-$DepsVersion-win64.msi"

    Write-Host "Downloading $msiUrl..." -ForegroundColor White
    Invoke-WebRequest -Uri $msiUrl -OutFile $tempMsi -UseBasicParsing

    Write-Host "Installing OpenUTVDeps (silent MSI install)..." -ForegroundColor Yellow
    $msiProc = Start-Process msiexec.exe -ArgumentList "/i `"$tempMsi`" /qn /norestart MSIFASTINSTALL=7" -Wait -PassThru
    Remove-Item -Force $tempMsi -ErrorAction SilentlyContinue

    if ($msiProc.ExitCode -ne 0 -and $msiProc.ExitCode -ne 3010) {
        Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue
        Write-Error "Failed to install OpenUTVDeps MSI. Exit code: $($msiProc.ExitCode)"
        return
    }
    Write-Host "OpenUTVDeps $DepsVersion installed successfully!" -ForegroundColor Green
} else {
    Write-Host "Skipping OpenUTVDeps download/install (-SkipDeps)." -ForegroundColor Gray
}

# Step 4: Install the application files
Write-Host "`n--- Installing OpenUTV into $InstallDir ---" -ForegroundColor Cyan
$installPrefix = $InstallDir.TrimEnd('\') + '\'
$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($installPrefix, [System.StringComparison]::OrdinalIgnoreCase) })
if ($running.Count -gt 0) {
    Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue
    Write-Error "OpenUTV is running from $InstallDir ($(($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', ')). Close it and run the installer again."
    return
}

# Replace what the package ships instead of copying over it: a file an earlier release had (a
# plugin, a launcher, .cmd wrappers) would otherwise stay and be loaded.
if (Test-Path $InstallDir) {
    foreach ($item in Get-ChildItem -LiteralPath $sourceDir) {
        $target = Join-Path $InstallDir $item.Name
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
}
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
& robocopy $sourceDir $InstallDir /E /MOVE /NDL /NFL /NJH /NJS /nc /ns /np | Out-Null
Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue

$binDir = Join-Path $InstallDir "bin"
$cmdDir = Join-Path $InstallDir "cmd"
$utvExe = Join-Path $binDir "utv.exe"
if (-not (Test-Path $utvExe)) {
    Write-Error "Installation failed: utv.exe was not found in $binDir"
    return
}

# Step 5: PATH
Write-Host "`n--- Configuring PATH ---" -ForegroundColor Cyan
Remove-LegacyEnvironment

# Only cmd (launchers) goes on PATH. Packages from before the launcher rework have no cmd directory;
# their bin goes on PATH as before.
$pathDir = if (Test-Path $cmdDir) { $cmdDir } else { $binDir }
function Select-OtherPathEntries([string]$path) {
    return ($path -split ";") | Where-Object {
        $_ -and
        $_ -notlike "*OpenUTVDeps*" -and
        $_ -notlike "*openutv-dependencies*" -and
        $_.TrimEnd('\') -ne $binDir.TrimEnd('\') -and
        $_.TrimEnd('\') -ne $cmdDir.TrimEnd('\')
    }
}
$persistentPath = [Environment]::GetEnvironmentVariable("Path", $pathScope)
[Environment]::SetEnvironmentVariable("Path", ((@($pathDir) + (Select-OtherPathEntries $persistentPath)) -join ";"), $pathScope)
$env:Path = (@($pathDir) + (Select-OtherPathEntries $env:Path)) -join ";"
Write-Host "  + Added to $pathScope PATH: $pathDir" -ForegroundColor Gray

# Step 6: Create Start Menu and Desktop Shortcuts
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

# Step 7: Register Windows Add/Remove Programs (ARP)
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
Write-Host "  2. Terminal:   utv, utvio, utvls, utvpkg, py-interp (in a new terminal)" -ForegroundColor Cyan
Write-Host "  3. Binary:     $utvExe`n" -ForegroundColor White
