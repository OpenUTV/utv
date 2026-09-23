$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$packageArgs = @{
  packageName   = 'openutv'
  unzipLocation = $toolsDir
  fileType      = 'zip'
  url64         = 'https://github.com/OpenUTV/utv/releases/download/2026.7/UTV-2026.7-windows-x64.zip'
  checksum64    = ''
  checksumType64= 'sha256'
}

Install-ChocolateyZipPackage @packageArgs

New-Item "$toolsDir\utv-windows-x64\bin\utv.exe.ignore" -Type File -Force | Out-Null

$targetPath = Join-Path $toolsDir "utv-windows-x64\bin\utv.exe"
Install-ChocolateyShortcut -shortcutFilePath "$env:PUBLIC\Desktop\OpenUTV.lnk" -targetPath $targetPath
Install-ChocolateyShortcut -shortcutFilePath "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OpenUTV.lnk" -targetPath $targetPath
