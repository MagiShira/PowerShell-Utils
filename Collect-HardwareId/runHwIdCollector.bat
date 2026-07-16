@echo off
setlocal

REM ============================ CONFIG ============================
REM  scriptFolder = path to the tool folder RELATIVE TO A DRIVE ROOT.
REM  The launcher searches every drive from D: to Z: for this folder,
REM  so you don't have to care which letter the USB gets assigned.
REM
REM  Example: with the value below, it looks for
REM      D:\PowerShell\kc118-intuneHwIdCollector\collector.ps1
REM      E:\PowerShell\kc118-intuneHwIdCollector\collector.ps1  ... etc.
REM
REM  Change this one line to match where you put the files on your USB.
set scriptFolder=PowerShell\kc118-intuneHwIdCollector

REM  Extra arguments passed to collector.ps1 on every run (optional).
REM  e.g.  set collectorArgs=-GroupTag "Kiosk"
set collectorArgs=
REM ===============================================================

set foundFolder=false

for %%d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%d:\%scriptFolder%\" (
        echo Found folder at %%d:\%scriptFolder%\
        set foundFolder=true
        set folderPath=%%d:\%scriptFolder%
        goto :run
    )
)

:notfound
echo Folder %scriptFolder% not found on drives D: to Z:
echo Make sure the collector USB/drive is connected, then try again.
pause
exit /b 1

:run
cd /d "%folderPath%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%folderPath%\collector.ps1" %collectorArgs% %*
pause
