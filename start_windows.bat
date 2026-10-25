@echo off
setlocal EnableExtensions
title Daily Assistant - Windows
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] flutter was not found in PATH.
  echo Install Flutter or add its bin directory to PATH, then retry.
  pause
  exit /b 1
)

echo Running Flutter app on Windows ...
echo.
flutter run -d windows
if errorlevel 1 (
  echo.
  echo [ERROR] flutter run failed.
  pause
  exit /b 1
)
echo.
echo App stopped.
pause
exit /b 0
