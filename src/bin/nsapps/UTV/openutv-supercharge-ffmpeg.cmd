@echo off
setlocal
set "DIR=%~dp0"
if exist "%DIR%py-interp.exe" (
    "%DIR%py-interp.exe" "%DIR%openutv-supercharge-ffmpeg.py" %*
) else (
    python "%DIR%openutv-supercharge-ffmpeg.py" %*
)
