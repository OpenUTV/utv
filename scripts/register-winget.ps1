<#
.SYNOPSIS
    Registers OpenUTV with the official Windows Package Manager (winget-pkgs).
.DESCRIPTION
    Installs wingetcreate if needed, generates package manifests for OpenUTV.UTV,
    validates the manifest schema, and submits the initial Pull Request to microsoft/winget-pkgs.
#>
[CmdletBinding()]
param(
    [string]$Version = "2026.7",
    [string]$PackageIdentifier = "OpenUTV.UTV",
    [switch]$Submit = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=== OpenUTV Windows Package Manager (winget) Registration ===" -ForegroundColor Cyan

# 1. Ensure wingetcreate is installed
if (-not (Get-Command wingetcreate -ErrorAction SilentlyContinue)) {
    Write-Host "Installing wingetcreate CLI tool..." -ForegroundColor Yellow
    winget install Microsoft.WingetCreate --accept-source-agreements --accept-package-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

if (-not (Get-Command wingetcreate -ErrorAction SilentlyContinue)) {
    Write-Error "Could not find wingetcreate in PATH. Please restart your terminal or install from https://github.com/microsoft/winget-create"
    return
}

$installerUrl = "https://github.com/OpenUTV/utv/releases/download/$Version/UTV-$Version-windows-x64.zip"
Write-Host "Target Release URL: $installerUrl" -ForegroundColor Green

# 2. Run wingetcreate to generate or update manifests
Write-Host "`nGenerating manifests for $PackageIdentifier version $Version..." -ForegroundColor Yellow
$manifestOutputDir = Join-Path $env:TEMP "winget-manifests-$PackageIdentifier-$Version"
New-Item -ItemType Directory -Force -Path $manifestOutputDir | Out-Null

# Run wingetcreate new
Write-Host "Launching wingetcreate wizard for initial package setup..." -ForegroundColor Cyan
Write-Host "Recommended responses when prompted:" -ForegroundColor White
Write-Host "  PackageIdentifier: $PackageIdentifier" -ForegroundColor Gray
Write-Host "  PackageName: OpenUTV" -ForegroundColor Gray
Write-Host "  Publisher: OpenUTV" -ForegroundColor Gray
Write-Host "  License: Apache-2.0" -ForegroundColor Gray
Write-Host "  ShortDescription: High-performance framecycler and sequence viewer for VFX and digital media" -ForegroundColor Gray
Write-Host "  InstallerType: zip" -ForegroundColor Gray
Write-Host "  NestedInstallerType: portable" -ForegroundColor Gray
Write-Host "  NestedInstallerFile: bin\utv.exe" -ForegroundColor Gray

if ($Submit) {
    wingetcreate new $installerUrl --output $manifestOutputDir --submit
} else {
    wingetcreate new $installerUrl --output $manifestOutputDir
    Write-Host "`nManifests generated in $manifestOutputDir" -ForegroundColor Green
    Write-Host "To submit to microsoft/winget-pkgs, re-run with -Submit or run:" -ForegroundColor White
    Write-Host "  wingetcreate submit $manifestOutputDir" -ForegroundColor Green
}
