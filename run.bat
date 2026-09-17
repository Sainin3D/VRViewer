@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

rem Prefer a portable Godot 4.7 next to project.godot, then common installs / PATH.
set "GODOT="

rem Exact known 4.7 editor builds in this folder (standard, not .NET).
if exist "%~dp0Godot_v4.7-stable_win64.exe" set "GODOT=%~dp0Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%~dp0Godot_v4.7.1-stable_win64.exe" set "GODOT=%~dp0Godot_v4.7.1-stable_win64.exe"

rem Any Godot 4.7* win64 editor dropped in this folder (skip console companion + .NET).
if not defined GODOT (
  for %%F in ("%~dp0Godot_v4.7*_win64.exe") do (
    echo %%~nxF | findstr /I /C:".console." >nul && goto :next4_7
    echo %%~nxF | findstr /I /C:"mono" /C:"dotnet" >nul && goto :next4_7
    set "GODOT=%%~fF"
    goto :have_godot
    :next4_7
  )
)

rem Broader portable fallback: any non-console Godot_*.exe in this folder.
if not defined GODOT (
  for %%F in ("%~dp0Godot_*.exe") do (
    echo %%~nxF | findstr /I /C:".console." >nul && goto :nextany
    echo %%~nxF | findstr /I /C:"mono" /C:"dotnet" >nul && goto :nextany
    set "GODOT=%%~fF"
    goto :have_godot
    :nextany
  )
)

rem Typical install locations.
if not defined GODOT if exist "%LocalAppData%\Godot\Godot_v4.7-stable_win64.exe" set "GODOT=%LocalAppData%\Godot\Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%ProgramFiles%\Godot\Godot_v4.7-stable_win64.exe" set "GODOT=%ProgramFiles%\Godot\Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%ProgramFiles%\Godot\Godot.exe" set "GODOT=%ProgramFiles%\Godot\Godot.exe"

rem On PATH (Scoop / manual / steamless installs that add a shim).
if not defined GODOT (
  where godot >nul 2>nul
  if not errorlevel 1 for /f "delims=" %%G in ('where godot') do (
    set "GODOT=%%G"
    goto :have_godot
  )
)

:have_godot
if not defined GODOT (
  echo.
  echo VR Viewer needs Godot 4.7 ^(standard Windows 64-bit, not the .NET build^).
  echo.
  echo Easiest for anyone picking this up:
  echo   1. Download Godot 4.7 from https://godotengine.org/download/windows/
  echo   2. Put Godot_v4.7-stable_win64.exe in THIS folder ^(next to project.godot^)
  echo   3. Double-click run.bat again
  echo.
  echo Or install Godot 4.7 system-wide / add `godot` to PATH, then run this script.
  echo We do not ship the Godot binary in git ^(size + license clarity^).
  echo.
  pause
  exit /b 1
)

if not exist "%~dp0project.godot" (
  echo project.godot is missing. Clone / copy the whole project folder, not just run.bat.
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
