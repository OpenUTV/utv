$ErrorActionPreference = 'Stop'

# AutoUninstaller handles MSI uninstalls automatically, but explicit uninstall script ensures speedup flags during uninstall
$packageArgs = @{
  packageName    = 'openutv-dependencies'
  fileType       = 'msi'
  silentArgs     = '{F4EDD980-1E8E-46D2-8BED-AEA5CDA6FD7E} /qn /norestart MSIFASTINSTALL=7 DISABLEROLLBACK=1'
  validExitCodes = @(0, 3010)
}

Uninstall-ChocolateyPackage @packageArgs
