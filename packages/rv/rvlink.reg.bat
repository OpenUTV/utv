@echo off
REM Check for administrative privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Success: Administrative privileges confirmed.
) else (
    echo Failure: Current permissions to execute this .BAT file are inadequate.
    echo Please run this script as an administrator.
    pause
    exit /b
)

cd /d %~dp0
pushd ..

REM Define the path to the executable
set "scriptDir=%cd%"
set "utvExePath=%scriptDir%\bin\utv.exe"

REM Check if the executable exists
if not exist "%utvExePath%" (
    echo Executable file %utvExePath% does not exist. Exiting script.
    popd
    pause
    exit /b
)

@echo on
REM Register utvlink protocol
reg add "HKCR\utvlink" /f
reg add "HKCR\utvlink" /ve /d "URL:UTV Protocol" /f
reg add "HKCR\utvlink" /v "URL Protocol" /d "" /f

reg add "HKCR\utvlink\DefaultIcon" /f
reg add "HKCR\utvlink\DefaultIcon" /ve /d "utv.exe,1" /f

reg add "HKCR\utvlink\shell" /f
reg add "HKCR\utvlink\shell\open" /f

reg add "HKCR\utvlink\shell\open\command" /f
reg add "HKCR\utvlink\shell\open\command" /ve /d "\"%utvExePath%\" \"%%1\"" /f

REM Also register rvlink protocol for compatibility
reg add "HKCR\rvlink" /f
reg add "HKCR\rvlink" /ve /d "URL:UTV Protocol" /f
reg add "HKCR\rvlink" /v "URL Protocol" /d "" /f

reg add "HKCR\rvlink\DefaultIcon" /f
reg add "HKCR\rvlink\DefaultIcon" /ve /d "utv.exe,1" /f

reg add "HKCR\rvlink\shell" /f
reg add "HKCR\rvlink\shell\open" /f

reg add "HKCR\rvlink\shell\open\command" /f
reg add "HKCR\rvlink\shell\open\command" /ve /d "\"%utvExePath%\" \"%%1\"" /f

popd
pause
