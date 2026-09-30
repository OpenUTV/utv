@echo off
setlocal

:: Discover OpenUTVDeps runtime root directory
set "DEPS_ROOT="
if defined UTV_DEPS_ROOT if exist "%UTV_DEPS_ROOT%\bin\OpenImageIO.dll" set "DEPS_ROOT=%UTV_DEPS_ROOT%"
if not defined DEPS_ROOT if defined OPENUTV_DEPS_ROOT if exist "%OPENUTV_DEPS_ROOT%\bin\OpenImageIO.dll" set "DEPS_ROOT=%OPENUTV_DEPS_ROOT%"

if not defined DEPS_ROOT (
    for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v "UTV_DEPS_ROOT" 2^>nul') do if exist "%%b\bin\OpenImageIO.dll" set "DEPS_ROOT=%%b"
)
if not defined DEPS_ROOT (
    for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v "UTV_DEPS_ROOT" 2^>nul') do if exist "%%b\bin\OpenImageIO.dll" set "DEPS_ROOT=%%b"
)
if not defined DEPS_ROOT (
    for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v "OPENUTV_DEPS_ROOT" 2^>nul') do if exist "%%b\bin\OpenImageIO.dll" set "DEPS_ROOT=%%b"
)
if not defined DEPS_ROOT (
    for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v "OPENUTV_DEPS_ROOT" 2^>nul') do if exist "%%b\bin\OpenImageIO.dll" set "DEPS_ROOT=%%b"
)
if not defined DEPS_ROOT (
    for /f "tokens=2*" %%a in ('reg query "HKCU\Software\OpenUTV" /v "DepsPath" 2^>nul') do if exist "%%b\bin\OpenImageIO.dll" set "DEPS_ROOT=%%b"
)
if not defined DEPS_ROOT (
    for /f "tokens=2*" %%a in ('reg query "HKLM\Software\OpenUTV" /v "DepsPath" 2^>nul') do if exist "%%b\bin\OpenImageIO.dll" set "DEPS_ROOT=%%b"
)
if not defined DEPS_ROOT (
    for /d %%d in ("%ProgramFiles%\OpenUTVDeps*") do if exist "%%d\bin\OpenImageIO.dll" set "DEPS_ROOT=%%d"
)
if not defined DEPS_ROOT (
    for /d %%d in ("%LOCALAPPDATA%\Programs\OpenUTVDeps*") do if exist "%%d\bin\OpenImageIO.dll" set "DEPS_ROOT=%%d"
)

if not defined DEPS_ROOT (
    echo OpenUTV: Could not locate OpenUTVDeps runtime dependencies. >&2
    exit /b 1
)

set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"

set "PATH=%APP_DIR%;%DEPS_ROOT%\bin;%DEPS_ROOT%\tools\python3\Lib\site-packages\PySide6;%DEPS_ROOT%\tools\python3;%DEPS_ROOT%\tools\python3\Scripts;%PATH%"
set "PYTHONHOME=%DEPS_ROOT%\tools\python3"
set "QT_PLUGIN_PATH=%DEPS_ROOT%\tools\python3\Lib\site-packages\PySide6\plugins"
set "QT_QPA_PLATFORM_PLUGIN_PATH=%DEPS_ROOT%\tools\python3\Lib\site-packages\PySide6\plugins\platforms"
set "UTV_DEPS_ROOT=%DEPS_ROOT%"
set "OPENUTV_DEPS_ROOT=%DEPS_ROOT%"
set "UTV_HOME=%APP_DIR%"
set "OPENUTV_HOME=%APP_DIR%"

%*
exit /b %ERRORLEVEL%
