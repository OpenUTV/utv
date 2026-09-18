@echo off
setlocal enabledelayedexpansion

:: Check if OPENUTV_DEPS_ROOT is already defined and valid
set "DEPS_BIN="
set "PYSIDE_DIR="
set "PYTHON_DIR="
if defined OPENUTV_DEPS_ROOT (
    if exist "%OPENUTV_DEPS_ROOT%\bin" (
        set "DEPS_BIN=%OPENUTV_DEPS_ROOT%\bin"
    )
    if exist "%OPENUTV_DEPS_ROOT%\tools\python3\Lib\site-packages\PySide6" (
        set "PYSIDE_DIR=%OPENUTV_DEPS_ROOT%\tools\python3\Lib\site-packages\PySide6"
        set "PYTHON_DIR=%OPENUTV_DEPS_ROOT%\tools\python3"
    )
)

:: If not found via OPENUTV_DEPS_ROOT, scan Program Files and common install locations
if not defined DEPS_BIN (
    for /d %%D in ("%ProgramFiles%\OpenUTVDeps *" "C:\Program Files\OpenUTVDeps *" "%LOCALAPPDATA%\OpenUTVDeps *" "C:\OpenUTVDeps*") do (
        if exist "%%~D\bin" (
            set "DEPS_BIN=%%~D\bin"
            set "OPENUTV_DEPS_ROOT=%%~D"
            if exist "%%~D\tools\python3\Lib\site-packages\PySide6" (
                set "PYSIDE_DIR=%%~D\tools\python3\Lib\site-packages\PySide6"
                set "PYTHON_DIR=%%~D\tools\python3"
            )
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

:: Configure environment
if defined PYSIDE_DIR (
    set "PATH=%~dp0;!PYSIDE_DIR!;!PYSIDE_DIR!\..\shiboken6;!DEPS_BIN!;!PYTHON_DIR!;!PATH!"
    if not defined QT_PLUGIN_PATH set "QT_PLUGIN_PATH=!PYSIDE_DIR!\plugins"
    if not defined QTWEBENGINEPROCESS_PATH set "QTWEBENGINEPROCESS_PATH=!PYSIDE_DIR!\QtWebEngineProcess.exe"
    if not defined QTWEBENGINE_RESOURCES_PATH set "QTWEBENGINE_RESOURCES_PATH=!PYSIDE_DIR!\resources"
    if not defined QTWEBENGINE_LOCALES_PATH set "QTWEBENGINE_LOCALES_PATH=!PYSIDE_DIR!\translations\qtwebengine_locales"
    if not defined QML2_IMPORT_PATH set "QML2_IMPORT_PATH=!PYSIDE_DIR!\qml"
) else (
    set "PATH=%~dp0;%DEPS_BIN%;%PATH%"
)

if not defined PYTHONHOME if defined PYTHON_DIR set "PYTHONHOME=%PYTHON_DIR%"

:: Software OpenGL fallback for VM/RDP
if not "%SESSIONNAME%"=="" if not "%SESSIONNAME%"=="Console" if not defined QT_OPENGL set "NEED_SW_GL=1"
if "%~1"=="--software-gl" set "NEED_SW_GL=1"
if "%~1"=="-software-gl" set "NEED_SW_GL=1"
if defined NEED_SW_GL (
    if not exist "%~dp0opengl32.dll" (
        if exist "%~dp0opengl32sw.dll" copy /y "%~dp0opengl32sw.dll" "%~dp0opengl32.dll" >nul 2>&1
        if not exist "%~dp0opengl32.dll" if defined PYSIDE_DIR if exist "!PYSIDE_DIR!\opengl32sw.dll" copy /y "!PYSIDE_DIR!\opengl32sw.dll" "%~dp0opengl32.dll" >nul 2>&1
    )
    set "QT_OPENGL=desktop"
)

:: Launch the actual UTV binary
if exist "%~dp0utv-bin.exe" (
    start "" "%~dp0utv-bin.exe" %*
) else (
    start "" "%~dp0utv.exe" %*
)
