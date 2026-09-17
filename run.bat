@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

rem Default: run the app (main scene).  For the editor:  run.bat editor
set "GODOT="
set "MODE=play"
if /I "%~1"=="editor" (
  set "MODE=editor"
  shift
)
if /I "%~1"=="play" (
  set "MODE=play"
  shift
)

if exist "%~dp0Godot_v4.7-stable_win64.exe" set "GODOT=%~dp0Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%~dp0Godot_v4.7.1-stable_win64.exe" set "GODOT=%~dp0Godot_v4.7.1-stable_win64.exe"

if not defined GODOT (
  for /f "delims=" %%F in ('dir /b /a:-d "%~dp0Godot_v4.7*_win64.exe" 2^>nul') do (
    set "N=%%F"
    set "SKIP=0"
    echo !N! | findstr /I ".console." >nul && set "SKIP=1"
    echo !N! | findstr /I "mono dotnet" >nul && set "SKIP=1"
    if "!SKIP!"=="0" if not defined GODOT set "GODOT=%~dp0%%F"
  )
)

if not defined GODOT (
  for /f "delims=" %%F in ('dir /b /a:-d "%~dp0Godot_*.exe" 2^>nul') do (
    set "N=%%F"
    set "SKIP=0"
    echo !N! | findstr /I ".console." >nul && set "SKIP=1"
    echo !N! | findstr /I "mono dotnet" >nul && set "SKIP=1"
    if "!SKIP!"=="0" if not defined GODOT set "GODOT=%~dp0%%F"
  )
)

if not defined GODOT if exist "%LocalAppData%\Godot\Godot_v4.7-stable_win64.exe" set "GODOT=%LocalAppData%\Godot\Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%ProgramFiles%\Godot\Godot_v4.7-stable_win64.exe" set "GODOT=%ProgramFiles%\Godot\Godot_v4.7-stable_win64.exe"
if not defined GODOT if exist "%ProgramFiles%\Godot\Godot.exe" set "GODOT=%ProgramFiles%\Godot\Godot.exe"

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
  echo VR Viewer needs Godot 4.7 ^(standard Windows 64-bit, not .NET^).
  echo Put Godot_v4.7-stable_win64.exe next to project.godot, then run again.
  echo Download: https://godotengine.org/download/windows/
  echo.
  pause
  exit /b 1
)

if not exist "%~dp0project.godot" (
  echo project.godot is missing.
  pause
  exit /b 1
)

echo Using:  %GODOT%
echo Project: %~dp0
if /I "%MODE%"=="editor" (
  echo Mode:    editor
  echo.
  "%GODOT%" -e --path "%~dp0." %*
) else (
  echo Mode:    app ^(main scene^)
  echo Tip:     for VR, start SteamVR first. Desktop view works without it.
  echo          Editor: run.bat editor
  echo.
  rem Run the game, not the editor. Forward any extra args after "play".
  "%GODOT%" --path "%~dp0." %*
)
set "ERR=!ERRORLEVEL!"

if not "!ERR!"=="0" (
  echo.
  echo Godot exited with code !ERR!.
  echo Log: %APPDATA%\Godot\app_userdata\VR Model Viewer\logs\godot.log
  echo.
  echo If the window flashed: try "run.bat editor", then press Play once imports finish.
  echo.
  pause
  exit /b !ERR!
)

exit /b 0
