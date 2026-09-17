@echo off
setlocal
set "DIR=%~dp0"
if exist "%DIR%py-interp.exe" (
    "%DIR%py-interp.exe" "%DIR%openutv-check-updates.py" %*
) else (
    python "%DIR%openutv-check-updates.py" %*
)
