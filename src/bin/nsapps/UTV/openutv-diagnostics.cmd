@echo off
:: py-interp.exe (the OpenUTV launcher) finds OpenUTVDeps and sets up Python. This file works from
:: <install>\bin and from <install>\cmd, which only has launchers.
setlocal
set "BIN=%~dp0"
if not exist "%BIN%openutv-diagnostics.py" set "BIN=%~dp0..\bin\"
"%BIN%py-interp.exe" "%BIN%openutv-diagnostics.py" %*
exit /b %ERRORLEVEL%
