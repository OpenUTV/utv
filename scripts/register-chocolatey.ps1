<#
.SYNOPSIS
    Packages and registers OpenUTV and OpenUTV Dependencies on the Chocolatey Community Repository.
.DESCRIPTION
    Creates Chocolatey packages for both openutv-dependencies (MSI package)
    and openutv (application package with declared dependency), builds the .nupkg files,
    and optionally publishes them to Chocolatey.
#>
[CmdletBinding()]
param(
    [string]$AppVersion = "2026.7",
    [string]$DepsVersion = "26.5",
    [string]$ApiKey = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== OpenUTV Chocolatey Package Registration ===" -ForegroundColor Cyan

# 1. Ensure choco is available, checking common install paths
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    $chocoBin = "C:\ProgramData\chocolatey\bin"
    if (Test-Path (Join-Path $chocoBin "choco.exe")) {
        $env:Path = "$chocoBin;" + $env:Path
        Write-Host "Located choco at $chocoBin (added to current session PATH)." -ForegroundColor Green
    } else {
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$machinePath;$userPath"
    }
}

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Chocolatey CLI (choco.exe) is not in PATH." -ForegroundColor Yellow
    Write-Host "Please restart your PowerShell terminal or install from https://chocolatey.org/install" -ForegroundColor White
    Write-Error "Chocolatey CLI not found."
    return
}

$repoRoot = (Get-Item $PSScriptRoot).Parent.FullName

# ========================================================
# 2. Package: openutv-dependencies
# ========================================================
Write-Host "`n--- Preparing openutv-dependencies Package (v$DepsVersion) ---" -ForegroundColor Cyan
$depsChocoDir = Join-Path $repoRoot "chocolatey\openutv-dependencies"
$depsToolsDir = Join-Path $depsChocoDir "tools"
New-Item -ItemType Directory -Force -Path $depsToolsDir | Out-Null

$depsMsiUrl = "https://github.com/OpenUTV/utv-dependencies/releases/download/v$DepsVersion/OpenUTVDeps-$DepsVersion-win64.msi"
$depsMsiSha = "2939e02f50d9c9877ed4615d9be35679491f37dfbd483fc7e793d71a0d365737"

$depsNuspec = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>openutv-dependencies</id>
    <version>$DepsVersion.0</version>
    <title>OpenUTV Dependencies</title>
    <authors>OpenUTV Contributors</authors>
    <owners>OpenUTV</owners>
    <projectUrl>https://openutv.com</projectUrl>
    <projectSourceUrl>https://github.com/OpenUTV/utv-dependencies</projectSourceUrl>
    <packageSourceUrl>https://github.com/OpenUTV/utv/tree/main/chocolatey/openutv-dependencies</packageSourceUrl>
    <iconUrl>https://raw.githubusercontent.com/OpenUTV/utv/main/src/lib/app/RvCommon/qrc/images/RV_icon.png</iconUrl>
    <releaseNotes>https://github.com/OpenUTV/utv-dependencies/releases/tag/v$DepsVersion</releaseNotes>
    <licenseUrl>https://github.com/OpenUTV/utv-dependencies/blob/main/LICENSE</licenseUrl>
    <copyright>Copyright (c) OpenUTV Contributors</copyright>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <docsUrl>https://github.com/OpenUTV/utv-dependencies/blob/main/README.md</docsUrl>
    <tags>openutv dependencies ffmpeg qt6 openexr ocio oiio vfx</tags>
    <summary>Relocatable multimedia runtime toolchain for OpenUTV</summary>
    <description>Compiled runtime dependencies and libraries (FFmpeg, Qt6, OpenEXR, OpenColorIO, OpenImageIO, Boost) for OpenUTV.</description>
  </metadata>
  <files>
    <file src="tools\**" target="tools" />
  </files>
</package>
"@
$depsNuspec | Set-Content -Path (Join-Path $depsChocoDir "openutv-dependencies.nuspec") -Encoding UTF8

$depsInstallPs1 = @"
`$ErrorActionPreference = 'Stop'
`$packageArgs = @{
  packageName   = 'openutv-dependencies'
  fileType      = 'msi'
  url64         = '$depsMsiUrl'
  silentArgs    = '/qn /norestart MSIFASTINSTALL=7 DISABLEROLLBACK=1'
  validExitCodes= @(0, 3010)
  checksum64    = '$depsMsiSha'
  checksumType64= 'sha256'
}

Install-ChocolateyPackage @packageArgs
"@
$depsInstallPs1 | Set-Content -Path (Join-Path $depsToolsDir "chocolateyInstall.ps1") -Encoding UTF8

$depsUninstallPs1 = @"
`$ErrorActionPreference = 'Stop'
`$packageArgs = @{
  packageName    = 'openutv-dependencies'
  fileType       = 'msi'
  silentArgs     = '{F4EDD980-1E8E-46D2-8BED-AEA5CDA6FD7E} /qn /norestart MSIFASTINSTALL=7 DISABLEROLLBACK=1'
  validExitCodes = @(0, 3010)
}

Uninstall-ChocolateyPackage @packageArgs
"@
$depsUninstallPs1 | Set-Content -Path (Join-Path $depsToolsDir "chocolateyUninstall.ps1") -Encoding UTF8

Write-Host "Packing openutv-dependencies.nupkg..." -ForegroundColor Yellow
choco pack (Join-Path $depsChocoDir "openutv-dependencies.nuspec") --outputdirectory $depsChocoDir

# ========================================================
# 3. Package: openutv (Main App with Dependency)
# ========================================================
Write-Host "`n--- Preparing openutv Application Package (v$AppVersion) ---" -ForegroundColor Cyan
$appChocoDir = Join-Path $repoRoot "chocolatey\openutv"
$appToolsDir = Join-Path $appChocoDir "tools"
New-Item -ItemType Directory -Force -Path $appToolsDir | Out-Null

$appZipUrl = "https://github.com/OpenUTV/utv/releases/download/$AppVersion/UTV-$AppVersion-windows-x64.zip"
Write-Host "Calculating SHA256 checksum for $appZipUrl..." -ForegroundColor Yellow
$tempZip = Join-Path $env:TEMP "utv-choco-sha.zip"
try {
    Invoke-WebRequest -Uri $appZipUrl -OutFile $tempZip -UseBasicParsing
    $appSha256 = (Get-FileHash -Path $tempZip -Algorithm SHA256).Hash.ToLower()
    Remove-Item -Force $tempZip
} catch {
    Write-Warning "Could not download $appZipUrl. Using placeholder."
    $appSha256 = "SHA256_HASH_PLACEHOLDER"
}

$appNuspec = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>openutv</id>
    <version>$AppVersion</version>
    <title>OpenUTV</title>
    <authors>OpenUTV Contributors</authors>
    <owners>OpenUTV</owners>
    <projectUrl>https://openutv.com</projectUrl>
    <projectSourceUrl>https://github.com/OpenUTV/utv</projectSourceUrl>
    <packageSourceUrl>https://github.com/OpenUTV/utv/tree/main/chocolatey/openutv</packageSourceUrl>
    <iconUrl>https://raw.githubusercontent.com/OpenUTV/utv/main/src/lib/app/RvCommon/qrc/images/RV_icon.png</iconUrl>
    <releaseNotes>https://github.com/OpenUTV/utv/releases/tag/$AppVersion</releaseNotes>
    <licenseUrl>https://github.com/OpenUTV/utv/blob/main/LICENSE</licenseUrl>
    <copyright>Copyright (c) OpenUTV Contributors</copyright>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <docsUrl>https://github.com/OpenUTV/utv/blob/main/README.md</docsUrl>
    <tags>openutv media-player sequence-viewer vfx rv video framecycler</tags>
    <summary>High-performance sequence viewer and media player for VFX, animation, and digital media</summary>
    <description>OpenUTV is a high-performance, open-source framecycler and sequence viewer designed for VFX, animation, editorial, and digital media review workflows.</description>
    <dependencies>
      <dependency id="openutv-dependencies" version="$DepsVersion.0" />
    </dependencies>
  </metadata>
  <files>
    <file src="tools\**" target="tools" />
  </files>
</package>
"@
$appNuspec | Set-Content -Path (Join-Path $appChocoDir "openutv.nuspec") -Encoding UTF8

$appInstallPs1 = @"
`$ErrorActionPreference = 'Stop'
`$toolsDir = "`$(Split-Path -parent `$MyInvocation.MyCommand.Definition)"
`$packageArgs = @{
  packageName   = 'openutv'
  unzipLocation = `$toolsDir
  fileType      = 'zip'
  url64         = '$appZipUrl'
  checksum64    = '$appSha256'
  checksumType64= 'sha256'
}

Install-ChocolateyZipPackage @packageArgs

New-Item "`$toolsDir\utv-windows-x64\bin\utv.exe.ignore" -Type File -Force | Out-Null

`$targetPath = Join-Path `$toolsDir "utv-windows-x64\bin\utv.exe"
Install-ChocolateyShortcut -shortcutFilePath "`$env:PUBLIC\Desktop\OpenUTV.lnk" -targetPath `$targetPath
Install-ChocolateyShortcut -shortcutFilePath "`$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OpenUTV.lnk" -targetPath `$targetPath
"@
$appInstallPs1 | Set-Content -Path (Join-Path $appToolsDir "chocolateyInstall.ps1") -Encoding UTF8

$appUninstallPs1 = @"
`$ErrorActionPreference = 'Stop'
`$toolsDir = "`$(Split-Path -parent `$MyInvocation.MyCommand.Definition)"

Remove-Item -Force -ErrorAction SilentlyContinue "`$env:PUBLIC\Desktop\OpenUTV.lnk"
Remove-Item -Force -ErrorAction SilentlyContinue "`$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OpenUTV.lnk"
`$appDir = Join-Path `$toolsDir "utv-windows-x64"
if (Test-Path `$appDir) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue `$appDir
}
"@
$appUninstallPs1 | Set-Content -Path (Join-Path $appToolsDir "chocolateyUninstall.ps1") -Encoding UTF8

Write-Host "Packing openutv.nupkg..." -ForegroundColor Yellow
choco pack (Join-Path $appChocoDir "openutv.nuspec") --outputdirectory $appChocoDir

# Publish if API key provided
if ($ApiKey) {
    Write-Host "`nPublishing packages to Chocolatey Community Repository..." -ForegroundColor Yellow
    $depsPkg = (Get-ChildItem $depsChocoDir\*.nupkg | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    $appPkg = (Get-ChildItem $appChocoDir\*.nupkg | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName

    Write-Host "Pushing $depsPkg..." -ForegroundColor White
    choco push $depsPkg --source https://push.chocolatey.org/ --api-key $ApiKey
    Write-Host "Pushing $appPkg..." -ForegroundColor White
    choco push $appPkg --source https://push.chocolatey.org/ --api-key $ApiKey
    Write-Host "Both packages submitted to Chocolatey!" -ForegroundColor Green
} else {
    Write-Host "`nPackages created successfully in chocolatey\openutv-dependencies and chocolatey\openutv" -ForegroundColor Green
    Write-Host "To push to Chocolatey with your API key, re-run with: -ApiKey <YOUR_KEY>" -ForegroundColor White
}
