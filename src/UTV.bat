@echo off
setlocal

:: If OPENUTV_DEPS_ROOT is set, prepend its bin directory to PATH
if defined OPENUTV_DEPS_ROOT (
    set "PATH=%OPENUTV_DEPS_ROOT%\x64-windows\bin;%PATH%"
)

:: Launch the actual UTV executable
start "" "%~dp0utv.exe" %*
