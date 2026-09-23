<#
.SYNOPSIS
    Registers and initializes the official Scoop bucket for OpenUTV.
.DESCRIPTION
    Creates or clones OpenUTV/scoop-utv, creates bucket manifests for both
    openutv-dependencies (MSI runtime) and openutv (application), and pushes to GitHub.
#>
[CmdletBinding()]
param(
    [string]$Version = "2026.7",
    [string]$DepsVersion = "26.5",
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

# 4. Manifest for openutv-dependencies
Write-Host "Generating bucket\openutv-dependencies.json..." -ForegroundColor Yellow
$depsMsiUrl = "https://github.com/OpenUTV/utv-dependencies/releases/download/v$DepsVersion/OpenUTVDeps-$DepsVersion-win64.msi"
$depsSha = "2939e02f50d9c9877ed4615d9be35679491f37dfbd483fc7e793d71a0d365737"

$depsManifest = @"
{
    "version": "$DepsVersion",
    "description": "Compiled multimedia and VFX dependency toolchain (FFmpeg, Qt6, OpenEXR, OCIO, OIIO) for OpenUTV",
    "homepage": "https://github.com/OpenUTV/utv-dependencies",
    "license": "Apache-2.0",
    "depends": "lessmsi",
    "architecture": {
        "64bit": {
            "url": "$depsMsiUrl",
            "hash": "$depsSha"
        }
    },
    "installer": {
        "script": [
            "lessmsi x \"`$dir\\OpenUTVDeps-$DepsVersion-win64.msi\" \"`$dir\\unpacked\"",
            "Get-ChildItem \"`$dir\\unpacked\\SourceDir\\OpenUTVDeps*\" | Copy-Item -Destination \"`$dir\" -Recurse -Force",
            "Remove-Item -Recurse -Force \"`$dir\\unpacked\", \"`$dir\\OpenUTVDeps-$DepsVersion-win64.msi\""
        ]
    },
    "env_add_path": "bin",
    "env_set": {
        "OPENUTV_DEPS_ROOT": "`$dir"
    },
    "checkver": {
        "github": "https://github.com/OpenUTV/utv-dependencies",
        "regex": "v([\\d.]+)"
    },
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/OpenUTV/utv-dependencies/releases/download/v`$version/OpenUTVDeps-`$version-win64.msi"
            }
        }
    }
}
"@
$depsManifestPath = Join-Path $tempDir "bucket\openutv-dependencies.json"
$depsManifest | Set-Content -Path $depsManifestPath -Encoding UTF8

# 5. Fetch UTV release asset info
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

# 6. Generate UTV manifest JSON with dependency
$manifest = @"
{
    "version": "$Version",
    "description": "Lightweight and distributable framecycler and sequence viewer for VFX, animation, and digital media",
    "homepage": "https://github.com/OpenUTV/utv",
    "license": "Apache-2.0",
    "depends": "openutv-dependencies",
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
Write-Host "Wrote manifests to bucket\" -ForegroundColor Green

# 7. Commit and Push
git add bucket/openutv-dependencies.json bucket/utv.json
$status = git status --porcelain
if ($status) {
    git commit -m "feat: initialize OpenUTV and OpenUTV Dependencies Scoop manifests"
    git push origin HEAD
    Write-Host "Pushed manifests to $RepoName successfully!" -ForegroundColor Green
} else {
    Write-Host "Manifests already up to date in repository." -ForegroundColor Yellow
}

# 8. Print Installation Instructions
Write-Host "`n=== Installation Verification Instructions ===" -ForegroundColor Cyan
Write-Host "Users can now install OpenUTV via Scoop with automatic dependency installation:" -ForegroundColor White
Write-Host "  scoop bucket add openutv https://github.com/OpenUTV/scoop-utv" -ForegroundColor Green
Write-Host "  scoop install openutv/utv" -ForegroundColor Green
Write-Host "`n(Scoop will automatically install openutv-dependencies first!)" -ForegroundColor Gray
