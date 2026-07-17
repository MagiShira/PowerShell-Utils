@echo off
setlocal enabledelayedexpansion

REM ============================ CONFIG ============================
REM  scriptFolder = path to the tool folder RELATIVE TO A DRIVE ROOT.
REM  The launcher searches every drive from D: to Z: for collector.ps1
REM  inside this folder, so you don't have to care which letter the USB
REM  gets assigned.
REM
REM  Example: with the value below, it looks for
REM      D:\PowerShell\kc118-intuneHwIdCollector\collector.ps1
REM      E:\PowerShell\kc118-intuneHwIdCollector\collector.ps1  ... etc.
REM
REM  Leave this BLANK (or set it to a single backslash "\") to look for
REM  collector.ps1 in the DRIVE ROOT itself, e.g. D:\collector.ps1.
REM
REM  Change this one line to match where you put the files on your USB.
set scriptFolder=PowerShell\kc118-intuneHwIdCollector

REM  Extra arguments passed to collector.ps1 on every run (optional).
REM  e.g.  set collectorArgs=-GroupTag "Kiosk"
set collectorArgs=
REM ===============================================================

REM  Normalize the configured path: treat "\" or empty as "the drive root",
REM  and strip a stray trailing backslash so we don't build "D:\\collector.ps1".
if "%scriptFolder%"=="\" set "scriptFolder="
if defined scriptFolder if "%scriptFolder:~-1%"=="\" set "scriptFolder=%scriptFolder:~0,-1%"
if defined scriptFolder if "%scriptFolder:~0,1%"=="\" set "scriptFolder=%scriptFolder:~1%"

for %%d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if defined scriptFolder (
        set "folderPath=%%d:\!scriptFolder!"
    ) else (
        set "folderPath=%%d:"
    )
    if exist "!folderPath!\collector.ps1" (
        echo Found collector at !folderPath!\collector.ps1
        goto :run
    )
)

:notfound
if defined scriptFolder (
    echo collector.ps1 not found in %scriptFolder% on any drive from D: to Z:.
) else (
    echo collector.ps1 not found in the root of any drive from D: to Z:.
)
echo Make sure the collector USB/drive is connected, then try again.
pause
exit /b 1

:run
cd /d "%folderPath%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%folderPath%\collector.ps1" %collectorArgs% %*
pause
