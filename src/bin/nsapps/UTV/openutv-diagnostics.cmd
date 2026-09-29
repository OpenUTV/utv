@echo off
setlocal enabledelayedexpansion
set "DIR=%~dp0"

:: 1. Discover OpenUTVDeps Root
if not defined OPENUTV_DEPS_ROOT (
    for /f "tokens=2*" %%a in ('reg query "HKCU\Software\OpenUTV" /v "DepsPath" 2^>nul') do set "OPENUTV_DEPS_ROOT=%%b"
)
if not defined OPENUTV_DEPS_ROOT (
    for /f "tokens=2*" %%a in ('reg query "HKLM\Software\OpenUTV" /v "DepsPath" 2^>nul') do set "OPENUTV_DEPS_ROOT=%%b"
)
if not defined OPENUTV_DEPS_ROOT (
    for /d %%d in ("%ProgramFiles%\OpenUTVDeps*") do if exist "%%d\bin\OpenImageIO.dll" set "OPENUTV_DEPS_ROOT=%%d"
)
if not defined OPENUTV_DEPS_ROOT (
    for /d %%d in ("%LOCALAPPDATA%\Programs\OpenUTVDeps*") do if exist "%%d\bin\OpenImageIO.dll" set "OPENUTV_DEPS_ROOT=%%d"
)

:: 2. Configure Environment if Dependencies Found
if defined OPENUTV_DEPS_ROOT (
    set "DEPS_BIN=%OPENUTV_DEPS_ROOT%\bin"
    set "DEPS_PY=%OPENUTV_DEPS_ROOT%\tools\python3"
    set "DEPS_PYSIDE=%OPENUTV_DEPS_ROOT%\tools\python3\Lib\site-packages\PySide6"
    set "PATH=!DEPS_BIN!;!DEPS_PY!;!DEPS_PYSIDE!;%DIR%;!PATH!"
    if not defined PYTHONHOME set "PYTHONHOME=!DEPS_PY!"
    if not defined QT_PLUGIN_PATH if exist "!DEPS_PYSIDE!\plugins" set "QT_PLUGIN_PATH=!DEPS_PYSIDE!\plugins"
    if not defined QT_QPA_PLATFORM_PLUGIN_PATH if exist "!DEPS_PYSIDE!\plugins\platforms" set "QT_QPA_PLATFORM_PLUGIN_PATH=!DEPS_PYSIDE!\plugins\platforms"
)

:: 3. Remove orphaned legacy qt.conf if present without plugins\Qt
if exist "%DIR%qt.conf" if not exist "%DIR%..\plugins\Qt" del /f /q "%DIR%qt.conf" >nul 2>&1

:: 4. Execute Diagnostics
if exist "%DIR%py-interp.exe" (
    "%DIR%py-interp.exe" "%DIR%openutv-diagnostics.py" %*
) else if defined DEPS_PY if exist "!DEPS_PY!\python.exe" (
    "!DEPS_PY!\python.exe" "%DIR%openutv-diagnostics.py" %*
) else (
    python "%DIR%openutv-diagnostics.py" %*
)
exit /b %ERRORLEVEL%
