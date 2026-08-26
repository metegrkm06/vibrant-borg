@echo off
title Install BonayCamera Virtual Webcam Driver
echo ===================================================
echo     BonayCamera DirectShow Driver Installer
echo ===================================================
echo.

:: Check for administrative privileges
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges to register BonayCamera...
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
    echo Registering BonayCamera 32-bit driver...
    regsvr32.exe /s /i:UnityCaptureName=BonayCamera "UnityCaptureFilter32.dll"
    echo Registering BonayCamera 64-bit driver...
    regsvr32.exe /s /i:UnityCaptureName=BonayCamera "UnityCaptureFilter64.dll"
    
    echo.
    echo ===================================================
    echo  [SUCCESS] BonayCamera is now registered!
    echo  You can now select "BonayCamera" in:
    echo  - Discord
    echo  - OBS Studio
    echo  - Zoom / Microsoft Teams
    echo  - Google Meet / Chrome
    echo ===================================================
    echo.
    pause
