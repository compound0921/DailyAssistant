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

if not defined ANDROID_HOME set "ANDROID_HOME=D:\Android\Sdk"
if not defined ANDROID_SDK_ROOT set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
if not defined ANDROID_AVD_HOME set "ANDROID_AVD_HOME=D:\Android\avd"

set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"
set "EMULATOR=%ANDROID_HOME%\emulator\emulator.exe"
set "AVD_NAME=daily_assistant_phone"
set "DEVICE_ID=emulator-5554"

if not exist "%ADB%" (
  echo [ERROR] adb not found: %ADB%
  pause
  exit /b 1
)
if not exist "%EMULATOR%" (
  echo [ERROR] emulator not found: %EMULATOR%
  pause
  exit /b 1
)

"%ADB%" devices | findstr /C:"%DEVICE_ID%" >nul
if errorlevel 1 (
  echo Starting emulator %AVD_NAME% ...
  rem Software rendering is more stable than -gpu host on this machine.
  start "Android Emulator" "%EMULATOR%" -avd %AVD_NAME% -gpu swiftshader_indirect -no-snapshot-load
) else (
  echo Emulator process already detected.
)

set /a WAIT=0
:wait_online
"%ADB%" -s %DEVICE_ID% get-state 2>nul | findstr /C:"device" >nul
if not errorlevel 1 goto wait_boot
set /a WAIT+=2
if %WAIT% GEQ 300 (
  echo [ERROR] Emulator did not come online within 300 seconds.
  echo If it is stuck offline, close the emulator process and run this script again.
  pause
  exit /b 1
)
"%SystemRoot%\System32\ping.exe" -n 3 127.0.0.1 >nul
goto wait_online

:wait_boot
set /a WAIT=0
:wait_boot_loop
set "BOOTED="
for /f "delims=" %%b in ('"%ADB%" -s %DEVICE_ID% shell getprop sys.boot_completed 2^>nul') do set "BOOTED=%%b"
if "%BOOTED%"=="1" goto booted
set /a WAIT+=2
if %WAIT% GEQ 300 (
  echo [ERROR] Emulator boot timed out.
  pause
  exit /b 1
)
"%SystemRoot%\System32\ping.exe" -n 3 127.0.0.1 >nul
goto wait_boot_loop

:booted
echo Emulator is ready.
echo Opening Flutter dev console for %DEVICE_ID% ...
start "Daily Assistant - Flutter Android" cmd /k "flutter run -d %DEVICE_ID%"
exit /b 0
