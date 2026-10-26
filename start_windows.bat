@echo off
setlocal EnableExtensions
title Daily Assistant - Hot Reload
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] flutter was not found in PATH.
  echo Install Flutter or add its bin directory to PATH, then retry.
  pause
  exit /b 1
)

echo Opening Flutter dev console for Windows ...
start "Daily Assistant - Flutter Windows" cmd /k "flutter run -d windows"
exit /b 0
