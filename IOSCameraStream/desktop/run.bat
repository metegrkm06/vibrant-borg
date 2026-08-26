@echo off
title BonayCamera Studio
cd /d "%~dp0"
python main.py
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to start BonayCamera. Press any key to exit...
    pause >nul
)
