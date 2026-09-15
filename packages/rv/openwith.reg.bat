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
REM Create registry keys and values for utv.exe
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\utv.exe" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\utv.exe" /ve /d "%utvExePath%" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\utv.exe" /v "Path" /d "%scriptDir%\bin" /f

reg add "HKCR\Applications\utv.exe\shell\open" /f
reg add "HKCR\Applications\utv.exe\shell\open" /v "FriendlyAppName" /d "UTV" /f

reg add "HKCR\Applications\utv.exe\shell\open\command" /f
reg add "HKCR\Applications\utv.exe\shell\open\command" /ve /d "\"%utvExePath%\" \"%%1\"" /f

reg add "HKCR\Applications\utv.exe\SupportedTypes" /f
for %%A in (3gp aces aif aifc aiff ari au avi bmp bw cin cineon cur cut dds dpx exr gif hdr ico iff j2c j2k jp2 jpeg jpg jpt lbm lif lmp mdl mov movieproc mp4 mraysubfile openexr pbm pcd pcx pdf pgm pic png ppm psd qt rgb rgba rgbe rla rpf sgi shd sm snd stdinfb sxr targa tdl tex tga tif tiff tpic tx txr txt wal wav yuv z zfile) do (
    reg add "HKCR\Applications\utv.exe\SupportedTypes" /v %%A /d "" /f
)

REM Also register rv.exe for backward compatibility
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\rv.exe" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\rv.exe" /ve /d "%utvExePath%" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\rv.exe" /v "Path" /d "%scriptDir%\bin" /f

reg add "HKCR\Applications\rv.exe\shell\open" /f
reg add "HKCR\Applications\rv.exe\shell\open" /v "FriendlyAppName" /d "UTV" /f

reg add "HKCR\Applications\rv.exe\shell\open\command" /f
reg add "HKCR\Applications\rv.exe\shell\open\command" /ve /d "\"%utvExePath%\" \"%%1\"" /f

reg add "HKCR\Applications\rv.exe\SupportedTypes" /f
for %%A in (3gp aces aif aifc aiff ari au avi bmp bw cin cineon cur cut dds dpx exr gif hdr ico iff j2c j2k jp2 jpeg jpg jpt lbm lif lmp mdl mov movieproc mp4 mraysubfile openexr pbm pcd pcx pdf pgm pic png ppm psd qt rgb rgba rgbe rla rpf sgi shd sm snd stdinfb sxr targa tdl tex tga tif tiff tpic tx txr txt wal wav yuv z zfile) do (
    reg add "HKCR\Applications\rv.exe\SupportedTypes" /v %%A /d "" /f
)

popd
pause
