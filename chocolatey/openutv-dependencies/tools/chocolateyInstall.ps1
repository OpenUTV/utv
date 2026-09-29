$ErrorActionPreference = 'Stop'

# Detect existing OpenUTV dependencies to avoid redundant 1.5GB download and reinstall
$existingDeps = $null
if ($env:OPENUTV_DEPS_ROOT -and (Test-Path "$env:OPENUTV_DEPS_ROOT\bin\OpenImageIO.dll")) {
  $existingDeps = $env:OPENUTV_DEPS_ROOT
} elseif (Test-Path "C:\Program Files\OpenUTVDeps 26.5\bin\OpenImageIO.dll") {
  $existingDeps = "C:\Program Files\OpenUTVDeps 26.5"
} else {
  $uninst = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "OpenUTVDeps 26.5*" -or $_.DisplayName -like "OpenUTV Dependencies 26.5*" }
  if ($uninst) {
    $existingDeps = $uninst.InstallLocation
  }
}

if ($existingDeps) {
  Write-Host "OpenUTV Dependencies (26.5) already detected at '$existingDeps'. Skipping download and installation." -ForegroundColor Green
  return
}

$packageArgs = @{
  packageName   = 'openutv-dependencies'
  fileType      = 'msi'
  url64         = 'https://github.com/OpenUTV/utv-dependencies/releases/download/v26.5/OpenUTVDeps-26.5-win64.msi'
  silentArgs    = '/qn /norestart MSIFASTINSTALL=7 DISABLEROLLBACK=1'
  validExitCodes= @(0, 3010)
  checksum64    = '2939e02f50d9c9877ed4615d9be35679491f37dfbd483fc7e793d71a0d365737'
  checksumType64= 'sha256'
}

Install-ChocolateyPackage @packageArgs

