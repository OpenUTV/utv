@echo off
setlocal enabledelayedexpansion

:: Check if OPENUTV_DEPS_ROOT is already defined and valid
set "DEPS_BIN="
if defined OPENUTV_DEPS_ROOT (
    if exist "%OPENUTV_DEPS_ROOT%\bin" (
        set "DEPS_BIN=%OPENUTV_DEPS_ROOT%\bin"
    ) else if exist "%OPENUTV_DEPS_ROOT%\x64-windows\bin" (
        set "DEPS_BIN=%OPENUTV_DEPS_ROOT%\x64-windows\bin"
    )
)

:: If not found via OPENUTV_DEPS_ROOT, scan Program Files
if not defined DEPS_BIN (
    for /d %%D in ("%ProgramFiles%\OpenUTVDeps *" "C:\Program Files\OpenUTVDeps *") do (
        if exist "%%~D\bin" (
            set "DEPS_BIN=%%~D\bin"
            set "OPENUTV_DEPS_ROOT=%%~D"
        ) else if exist "%%~D\installed\x64-windows\bin" (
            set "DEPS_BIN=%%~D\installed\x64-windows\bin"
            set "OPENUTV_DEPS_ROOT=%%~D"
        )
    )
)

:: If still not found, alert user and offer download link
if not defined DEPS_BIN (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$wshell = New-Object -ComObject Wscript.Shell; " ^
        "$choice = $wshell.Popup('OpenUTV requires the OpenUTVDeps package (FFmpeg, Python, Qt, OpenColorIO, OpenEXR) which was not found on this computer.`n`nWould you like to open the OpenUTV Dependencies download page now?', 0, 'OpenUTV - Dependencies Required', 4 + 48); " ^
        "if ($choice -eq 6) { Start-Process 'https://github.com/OpenUTV/utv-dependencies/releases/latest' }"
    exit /b 1
)

:: Add dependencies bin to PATH
set "PATH=%DEPS_BIN%;%PATH%"

:: Launch the actual UTV executable
start "" "%~dp0utv.exe" %*
