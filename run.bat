@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

rem ---------------------------------------------------------------------------
rem Find Godot 4.7: portable exe in this folder, then installs, then PATH.
rem Default: open the EDITOR (-e).  Use:  run.bat play   to run the main scene.
rem ---------------------------------------------------------------------------

set "GODOT="
set "MODE=editor"
if /I "%~1"=="play" (
  set "MODE=play"
  shift
)
if /I "%~1"=="editor" (
  set "MODE=editor"
  shift
)

rem Exact filenames people usually drop here.
if exist "%~dp0Godot_v4.7-stable_win64.exe" set "GODOT=%~dp0Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%~dp0Godot_v4.7.1-stable_win64.exe" set "GODOT=%~dp0Godot_v4.7.1-stable_win64.exe"
if not defined GODOT if exist "%~dp0Godot_v4.7-stable_win64_console.exe" (
  rem Prefer the non-console build if both exist; console is fine as last portable resort later.
)

rem Scan folder for Godot_v4.7*_win64.exe (skip console / mono / dotnet).
if not defined GODOT (
  for /f "delims=" %%F in ('dir /b /a:-d "%~dp0Godot_v4.7*_win64.exe" 2^>nul') do (
    set "N=%%F"
    set "SKIP=0"
    echo !N! | findstr /I ".console." >nul && set "SKIP=1"
    echo !N! | findstr /I "mono dotnet" >nul && set "SKIP=1"
    if "!SKIP!"=="0" if not defined GODOT set "GODOT=%~dp0%%F"
  )
)

rem Broader portable: any Godot_*.exe that is not console/dotnet.
if not defined GODOT (
  for /f "delims=" %%F in ('dir /b /a:-d "%~dp0Godot_*.exe" 2^>nul') do (
    set "N=%%F"
    set "SKIP=0"
    echo !N! | findstr /I ".console." >nul && set "SKIP=1"
    echo !N! | findstr /I "mono dotnet" >nul && set "SKIP=1"
    if "!SKIP!"=="0" if not defined GODOT set "GODOT=%~dp0%%F"
  )
)

rem Install locations.
if not defined GODOT if exist "%LocalAppData%\Godot\Godot_v4.7-stable_win64.exe" set "GODOT=%LocalAppData%\Godot\Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%ProgramFiles%\Godot\Godot_v4.7-stable_win64.exe" set "GODOT=%ProgramFiles%\Godot\Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%ProgramFiles%\Godot\Godot.exe" set "GODOT=%ProgramFiles%\Godot\Godot.exe"

rem PATH shim.
if not defined GODOT (
  where godot >nul 2>nul
  if not errorlevel 1 (
    for /f "delims=" %%G in ('where godot') do (
      if not defined GODOT set "GODOT=%%G"
    )
  )
)

if not defined GODOT (
  echo.
  echo VR Viewer needs Godot 4.7 ^(standard Windows 64-bit, not the .NET build^).
  echo.
  echo   1. Download: https://godotengine.org/download/windows/
  echo   2. Put Godot_v4.7-stable_win64.exe next to project.godot
  echo   3. Double-click run.bat again
  echo.
  pause
  exit /b 1
)

if not exist "%~dp0project.godot" (
  echo project.godot is missing. Use the full project folder.
  echo.
  pause
  exit /b 1
)

echo Using:  %GODOT%
echo Project: %~dp0
if /I "%MODE%"=="play" (
  echo Mode:    play ^(main scene^)
  echo.
  "%GODOT%" --path "%~dp0." %*
) else (
  echo Mode:    editor
  echo.
  "%GODOT%" -e --path "%~dp0." %*
)
set "ERR=!ERRORLEVEL!"

if not "!ERR!"=="0" (
  echo.
  echo Godot exited with code !ERR!.
  echo Log: %APPDATA%\Godot\app_userdata\VR Model Viewer\logs\godot.log
  echo.
  pause
  exit /b !ERR!
)

rem If play mode returned 0 instantly, still give a beat when launched by double-click.
if /I "%MODE%"=="play" (
  echo.
  echo Play mode finished ^(exit 0^). If the window flashed, check the log above.
  pause
)

exit /b 0
