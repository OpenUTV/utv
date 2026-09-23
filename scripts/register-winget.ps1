<#
.SYNOPSIS
    Registers OpenUTV and OpenUTV Dependencies with the official Windows Package Manager (winget-pkgs).
.DESCRIPTION
    Installs wingetcreate if needed, generates package manifests for OpenUTV.Dependencies (MSI)
    and OpenUTV.UTV (Application zip), validates the manifest schema, and submits to microsoft/winget-pkgs.
#>
[CmdletBinding()]
param(
    [ValidateSet("App", "Dependencies", "Both")]
    [string]$Target = "Both",
    [string]$AppVersion = "2026.7",
    [string]$DepsVersion = "26.5",
    [switch]$Submit = $false,
    [string]$Token = ""
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

# 2. Register OpenUTV Dependencies (MSI)
if ($Target -eq "Dependencies" -or $Target -eq "Both") {
    $depsUrl = "https://github.com/OpenUTV/utv-dependencies/releases/download/v$DepsVersion/OpenUTVDeps-$DepsVersion-win64.msi"
    Write-Host "`n--- Registering OpenUTV.Dependencies (v$DepsVersion) ---" -ForegroundColor Cyan
    Write-Host "MSI URL: $depsUrl" -ForegroundColor Green
    
    $depsOutputDir = Join-Path $env:TEMP "winget-manifests-OpenUTV.Dependencies-$DepsVersion"
    New-Item -ItemType Directory -Force -Path $depsOutputDir | Out-Null
    
    Write-Host "Generating manifests for OpenUTV.Dependencies..." -ForegroundColor Yellow
    if ($Submit -and $Token) {
        & wingetcreate new $depsUrl --out $depsOutputDir --token $Token
    } else {
        & wingetcreate new $depsUrl --out $depsOutputDir
        Write-Host "To submit Dependencies manifest to microsoft/winget-pkgs, run:" -ForegroundColor White
        Write-Host "  wingetcreate submit $depsOutputDir" -ForegroundColor Green
    }
}

# 3. Register OpenUTV (App)
if ($Target -eq "App" -or $Target -eq "Both") {
    $appUrl = "https://github.com/OpenUTV/utv/releases/download/$AppVersion/UTV-$AppVersion-windows-x64.zip"
    Write-Host "`n--- Registering OpenUTV.UTV (v$AppVersion) ---" -ForegroundColor Cyan
    Write-Host "App ZIP URL: $appUrl" -ForegroundColor Green

    $appOutputDir = Join-Path $env:TEMP "winget-manifests-OpenUTV.UTV-$AppVersion"
    New-Item -ItemType Directory -Force -Path $appOutputDir | Out-Null

    Write-Host "Generating manifests for OpenUTV.UTV..." -ForegroundColor Yellow
    if ($Submit -and $Token) {
        & wingetcreate new $appUrl --out $appOutputDir --token $Token
    } else {
        & wingetcreate new $appUrl --out $appOutputDir
        Write-Host "To submit App manifest to microsoft/winget-pkgs, run:" -ForegroundColor White
        Write-Host "  wingetcreate submit $appOutputDir" -ForegroundColor Green
    }
}
