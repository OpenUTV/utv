<#
.SYNOPSIS
    Registers and initializes the official Scoop bucket for OpenUTV.
.DESCRIPTION
    Creates or clones OpenUTV/scoop-utv, creates bucket/utv.json with
    proper architecture, autoupdate, and shortcut rules, and pushes to GitHub.
#>
[CmdletBinding()]
param(
    [string]$Version = "2026.7",
    [string]$RepoName = "OpenUTV/scoop-utv"
)

$ErrorActionPreference = "Stop"

Write-Host "=== OpenUTV Scoop Bucket Registration ===" -ForegroundColor Cyan

# 1. Verify dependencies
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) is not installed or not in PATH. Please install with: winget install GitHub.cli"
    return
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is not installed or not in PATH."
    return
}

# 2. Check if repo exists, create if not (safely without terminating on 404 stderr)
Write-Host "Checking repository $RepoName..." -ForegroundColor Yellow
$repoExists = $false
try {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $null = & gh repo view $RepoName 2>&1
    if ($LASTEXITCODE -eq 0) {
        $repoExists = $true
    }
    $ErrorActionPreference = $prevEAP
} catch {
    $repoExists = $false
}

if (-not $repoExists) {
    Write-Host "Repository $RepoName does not exist. Creating public repository..." -ForegroundColor Green
    & gh repo create $RepoName --public --description "Official Scoop bucket for OpenUTV" -y
}

# 3. Clone or setup working directory
$tempDir = Join-Path $env:TEMP "scoop-utv-init-$(Get-Random)"
Write-Host "Cloning $RepoName into $tempDir..." -ForegroundColor Yellow
& gh repo clone $RepoName $tempDir
Set-Location $tempDir

# Ensure bucket directory exists
New-Item -ItemType Directory -Force -Path "bucket" | Out-Null

# 4. Fetch release asset info
$assetUrl = "https://github.com/OpenUTV/utv/releases/download/$Version/UTV-$Version-windows-x64.zip"
Write-Host "Calculating SHA256 for release $assetUrl..." -ForegroundColor Yellow
$tempZip = Join-Path $env:TEMP "utv-test-sha.zip"
try {
    Invoke-WebRequest -Uri $assetUrl -OutFile $tempZip -UseBasicParsing
    $sha256 = (Get-FileHash -Path $tempZip -Algorithm SHA256).Hash.ToLower()
    Remove-Item -Force $tempZip
} catch {
    Write-Warning "Could not download $assetUrl to calculate hash. Using placeholder."
    $sha256 = "SHA256_HASH_PLACEHOLDER"
}

# 5. Generate manifest JSON
$manifest = @"
{
    "version": "$Version",
    "description": "Lightweight and distributable framecycler and sequence viewer for VFX, animation, and digital media",
    "homepage": "https://github.com/OpenUTV/utv",
    "license": "Apache-2.0",
    "architecture": {
        "64bit": {
            "url": "https://github.com/OpenUTV/utv/releases/download/$Version/UTV-$Version-windows-x64.zip",
            "hash": "$sha256"
        }
    },
    "extract_dir": "utv-windows-x64",
    "bin": "bin\\utv.exe",
    "shortcuts": [
        [
            "bin\\utv.exe",
            "OpenUTV"
        ]
    ],
    "checkver": "github",
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/OpenUTV/utv/releases/download/\$version/UTV-\$version-windows-x64.zip"
            }
        },
        "extract_dir": "utv-windows-x64"
    }
}
"@

$manifestPath = Join-Path $tempDir "bucket\utv.json"
$manifest | Set-Content -Path $manifestPath -Encoding UTF8
Write-Host "Wrote manifest to $manifestPath" -ForegroundColor Green

# 6. Commit and Push
git add bucket/utv.json
$status = git status --porcelain
if ($status) {
    git commit -m "feat: initialize OpenUTV Scoop manifest for version $Version"
    git push origin HEAD
    Write-Host "Pushed initial manifest to $RepoName successfully!" -ForegroundColor Green
} else {
    Write-Host "Manifest already up to date in repository." -ForegroundColor Yellow
}

# 7. Print Installation Instructions
Write-Host "`n=== Installation Verification Instructions ===" -ForegroundColor Cyan
Write-Host "Users can now install OpenUTV via Scoop with:" -ForegroundColor White
Write-Host "  scoop bucket add openutv https://github.com/OpenUTV/scoop-utv" -ForegroundColor Green
Write-Host "  scoop install openutv/utv" -ForegroundColor Green
Write-Host "`nTo update in the future:" -ForegroundColor White
Write-Host "  scoop update utv" -ForegroundColor Green
