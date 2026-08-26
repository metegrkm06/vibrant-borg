@echo off
title Uninstall BonayCamera Virtual Webcam Driver
echo ===================================================
echo     BonayCamera Driver Uninstaller
echo ===================================================
echo.

>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges to unregister BonayCamera...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"
    regsvr32.exe /u /s "UnityCaptureFilter32.dll"
    regsvr32.exe /u /s "UnityCaptureFilter64.dll"
    echo.
    echo BonayCamera driver unregistered successfully.
    echo.
    pause
