@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "GODOT="
if exist "%~dp0Godot_v4.7-stable_win64.exe" set "GODOT=%~dp0Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%~dp0..\breach-log-3d\Godot_v4.7-stable_win64.exe" set "GODOT=%~dp0..\breach-log-3d\Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%ProgramFiles%\Godot\Godot_v4.7-stable_win64.exe" set "GODOT=%ProgramFiles%\Godot\Godot_v4.7-stable_win64.exe"
if not defined GODOT (
  where godot >nul 2>nul
  if not errorlevel 1 set "GODOT=godot"
)

if not defined GODOT (
  echo.
  echo VR Model Viewer is a Godot 4.7 project, not a standalone .exe.
  echo.
  echo On this PC, copy Godot_v4.7-stable_win64.exe into this folder
  echo ^(same folder as project.godot^) and run this script again.
  echo.
  echo Download: https://godotengine.org/download/windows/
  echo Use the standard 64-bit build, version 4.7, not the .NET build.
  echo.
  pause
  exit /b 1
)

if not exist "%~dp0project.godot" (
  echo project.godot is missing. Copy the whole vr-model-viewer folder, not just run.bat.
  echo.
  pause
  exit /b 1
)

echo Using: %GODOT%
echo Project: %~dp0
echo.
"%GODOT%" --path "%~dp0." %*
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo Godot exited with code %ERR%.
  echo Log: %%APPDATA%%\Godot\app_userdata\VR Model Viewer\logs\godot.log
  echo.
  pause
)
exit /b %ERR%
