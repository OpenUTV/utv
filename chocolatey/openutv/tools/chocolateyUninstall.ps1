$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

# Remove shortcuts
Remove-Item -Force -ErrorAction SilentlyContinue "$env:PUBLIC\Desktop\OpenUTV.lnk"
Remove-Item -Force -ErrorAction SilentlyContinue "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OpenUTV.lnk"

# Remove application directory
$appDir = Join-Path $toolsDir "utv-windows-x64"
if (Test-Path $appDir) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $appDir
}
