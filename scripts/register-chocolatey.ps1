<#
.SYNOPSIS
    Packages and registers OpenUTV on the Chocolatey Community Repository.
.DESCRIPTION
    Creates the Chocolatey package layout (nuspec, installation script,
    uninstallation script, verification document), builds the .nupkg file,
    and optionally publishes it to Chocolatey.
#>
[CmdletBinding()]
param(
    [string]$Version = "2026.7",
    [string]$ApiKey = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== OpenUTV Chocolatey Package Registration ===" -ForegroundColor Cyan

# 1. Ensure choco is available
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Error "Chocolatey CLI (choco.exe) is not installed or not in PATH. Please install from https://chocolatey.org/install"
    return
}

$repoRoot = (Get-Item $PSScriptRoot).Parent.FullName
$chocoDir = Join-Path $repoRoot "chocolatey"
$toolsDir = Join-Path $chocoDir "tools"

New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

$zipUrl = "https://github.com/OpenUTV/utv/releases/download/$Version/UTV-$Version-windows-x64.zip"
Write-Host "Calculating SHA256 checksum for $zipUrl..." -ForegroundColor Yellow
$tempZip = Join-Path $env:TEMP "utv-choco-sha.zip"
try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
    $sha256 = (Get-FileHash -Path $tempZip -Algorithm SHA256).Hash.ToLower()
    Remove-Item -Force $tempZip
} catch {
    Write-Warning "Could not download $zipUrl. Using placeholder."
    $sha256 = "SHA256_HASH_PLACEHOLDER"
}

# 2. Write utv.nuspec
$nuspec = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>openutv</id>
    <version>$Version</version>
    <title>OpenUTV</title>
    <authors>OpenUTV Contributors</authors>
    <owners>OpenUTV</owners>
    <projectUrl>https://github.com/OpenUTV/utv</projectUrl>
    <licenseUrl>https://github.com/OpenUTV/utv/blob/main/LICENSE</licenseUrl>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <projectSourceUrl>https://github.com/OpenUTV/utv</projectSourceUrl>
    <packageSourceUrl>https://github.com/OpenUTV/utv/tree/main/chocolatey</packageSourceUrl>
    <docsUrl>https://github.com/OpenUTV/utv/blob/main/README.md</docsUrl>
    <bugTrackerUrl>https://github.com/OpenUTV/utv/issues</bugTrackerUrl>
    <tags>openutv media-player sequence-viewer vfx rv video framecycler</tags>
    <summary>High-performance sequence viewer and media player for VFX, animation, and digital media</summary>
    <description>OpenUTV is a high-performance, open-source framecycler and sequence viewer designed for VFX, animation, editorial, and digital media review workflows.</description>
  </metadata>
  <files>
    <file src="tools\**" target="tools" />
  </files>
</package>
"@

$nuspecPath = Join-Path $chocoDir "openutv.nuspec"
$nuspec | Set-Content -Path $nuspecPath -Encoding UTF8
Write-Host "Wrote nuspec to $nuspecPath" -ForegroundColor Green

# 3. Write chocolateyInstall.ps1
$installPs1 = @"
`$ErrorActionPreference = 'Stop'
`$toolsDir = "`$(Split-Path -parent `$MyInvocation.MyCommand.Definition)"
`$packageArgs = @{
  packageName   = 'openutv'
  unzipLocation = `$toolsDir
  fileType      = 'zip'
  url64         = '$zipUrl'
  checksum64    = '$sha256'
  checksumType64= 'sha256'
}

Install-ChocolateyZipPackage @packageArgs

# Prevent shim creation for background launcher helpers
New-Item "`$toolsDir\utv-windows-x64\bin\utv.exe.ignore" -Type File -Force | Out-Null

# Create shortcuts
`$targetPath = Join-Path `$toolsDir "utv-windows-x64\bin\utv.exe"
Install-ChocolateyShortcut -shortcutFilePath "`$env:PUBLIC\Desktop\OpenUTV.lnk" -targetPath `$targetPath
Install-ChocolateyShortcut -shortcutFilePath "`$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OpenUTV.lnk" -targetPath `$targetPath
"@

$installPath = Join-Path $toolsDir "chocolateyInstall.ps1"
$installPs1 | Set-Content -Path $installPath -Encoding UTF8

# 4. Write chocolateyUninstall.ps1
$uninstallPs1 = @"
`$ErrorActionPreference = 'SilentlyContinue'
Remove-Item -Force "`$env:PUBLIC\Desktop\OpenUTV.lnk"
Remove-Item -Force "`$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OpenUTV.lnk"
"@

$uninstallPath = Join-Path $toolsDir "chocolateyUninstall.ps1"
$uninstallPs1 | Set-Content -Path $uninstallPath -Encoding UTF8

# 5. Write VERIFICATION.txt
$verification = @"
VERIFICATION
Verification is intended to assist the Chocolatey moderators and community
in verifying that this package's contents are trustworthy.

The distribution zip is downloaded directly from the official OpenUTV GitHub Release:
URL: $zipUrl
SHA256: $sha256

Checksum can be verified directly with PowerShell:
Get-FileHash -Algorithm SHA256 UTV-$Version-windows-x64.zip
"@

$verificationPath = Join-Path $toolsDir "VERIFICATION.txt"
$verification | Set-Content -Path $verificationPath -Encoding UTF8

# 6. Copy License
$licenseSrc = Join-Path $repoRoot "LICENSE"
if (Test-Path $licenseSrc) {
    Copy-Item $licenseSrc (Join-Path $toolsDir "LICENSE.txt") -Force
}

# 7. Pack .nupkg
Write-Host "Packing Chocolatey package..." -ForegroundColor Yellow
Set-Location $chocoDir
choco pack $nuspecPath --outputdirectory $chocoDir

$nupkg = Get-ChildItem (Join-Path $chocoDir "*.nupkg") | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($nupkg) {
    Write-Host "Created Chocolatey package: $($nupkg.FullName)" -ForegroundColor Green
    
    if ($ApiKey) {
        Write-Host "Publishing to Chocolatey Community Repository..." -ForegroundColor Yellow
        choco push $nupkg.FullName --source https://push.chocolatey.org/ --api-key $ApiKey
        Write-Host "Package submitted to Chocolatey! (Note: First submissions require 3-10 days human moderation review)" -ForegroundColor Green
    } else {
        Write-Host "`nTo publish this package to community.chocolatey.org:" -ForegroundColor White
        Write-Host "  choco push $($nupkg.FullName) --source https://push.chocolatey.org/ --api-key <YOUR_API_KEY>" -ForegroundColor Green
    }
}
