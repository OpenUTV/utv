$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$packageArgs = @{
  packageName   = 'openutv'
  unzipLocation = $toolsDir
  fileType      = 'zip'
  url64         = 'https://github.com/OpenUTV/utv/releases/download/2026.8/UTV-2026.8-windows-x64.zip'
  checksum64    = 'cb0e543e77d8d899dd914290c6a10fd84c3c0d9a7e51a7cf37c3d0797651fd96'
  checksumType64= 'sha256'
}

Install-ChocolateyZipPackage @packageArgs

New-Item "$toolsDir\utv-windows-x64\bin\utv.exe.ignore" -Type File -Force | Out-Null

$targetPath = Join-Path $toolsDir "utv-windows-x64\bin\utv.exe"
Install-ChocolateyShortcut -shortcutFilePath "$env:PUBLIC\Desktop\OpenUTV.lnk" -targetPath $targetPath
Install-ChocolateyShortcut -shortcutFilePath "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OpenUTV.lnk" -targetPath $targetPath
