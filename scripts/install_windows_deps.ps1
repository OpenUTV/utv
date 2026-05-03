param (
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"

$InstallDir = "$env:LOCALAPPDATA\utv-deps"
$RepoOwner = "OpenUTV"
$RepoName = "utv-dependencies"

Write-Host "Installing OpenUTV dependencies to $InstallDir..."

if ($Version -eq "latest") {
    $ReleaseUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/tags/windows-x64"
} else {
    $ReleaseUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/tags/windows-x64"
}

# Fetch release info
Write-Host "Fetching release information from $ReleaseUrl"
$Headers = @{
    "Accept" = "application/vnd.github.v3+json"
}

# Add authorization if provided (useful for private repositories or rate limits)
if ($env:GH_TOKEN) {
    $Headers["Authorization"] = "token $($env:GH_TOKEN)"
}

try {
    $ReleaseInfo = Invoke-RestMethod -Uri $ReleaseUrl -Headers $Headers
} catch {
    Write-Error "Failed to fetch release info. If the repository is private, ensure the GH_TOKEN environment variable is set."
    throw
}

$AssetUrl = $null
foreach ($asset in $ReleaseInfo.assets) {
    if ($asset.name -match "utv-deps-windows-x64.zip") {
        $AssetUrl = $asset.url
        break
    }
}

if (-not $AssetUrl) {
    Write-Error "Could not find utv-deps-windows-x64.zip in the release."
    throw
}

$ZipPath = "$env:TEMP\utv-deps-windows-x64.zip"

Write-Host "Downloading $AssetUrl to $ZipPath"
$Headers["Accept"] = "application/octet-stream"
Invoke-RestMethod -Uri $AssetUrl -Headers $Headers -OutFile $ZipPath

if (Test-Path $InstallDir) {
    Write-Host "Cleaning existing directory $InstallDir..."
    Remove-Item -Path $InstallDir -Recurse -Force
}

New-Item -ItemType Directory -Path $InstallDir | Out-Null

Write-Host "Extracting archive..."
Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force

Remove-Item -Path $ZipPath -Force

# Set the path permanently for the user
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$BinDir = "$InstallDir\x64-windows\bin" # vcpkg export puts it in architecture subfolder

if ($UserPath -notmatch [regex]::Escape($BinDir)) {
    Write-Host "Adding $BinDir to User PATH..."
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$BinDir", "User")
    Write-Host "Successfully added to PATH. You may need to restart your terminal or IDE."
} else {
    Write-Host "$BinDir is already in User PATH."
}

Write-Host "Done! Dependencies are installed in $InstallDir"
