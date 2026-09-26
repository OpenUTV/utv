$ErrorActionPreference = 'Stop'
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
