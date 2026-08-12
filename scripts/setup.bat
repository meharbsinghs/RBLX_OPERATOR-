@echo off
REM ============================================================================
REM  RBLX Operator - one-click setup (Windows)
REM  Double-click this file. It verifies the repo, then lets you choose:
REM    1) Push to GitHub     (installs Git + GitHub CLI, links your account,
REM                           creates the repo, pushes)
REM    2) Add to Studio      (installs Rojo if needed, builds the .rbxl)
REM    3) Open the desktop app (RBLX Operator Studio .exe, if built)
REM  This window NEVER closes silently - every message ends with a pause.
REM ============================================================================
setlocal
cd /d "%~dp0.."

echo.
echo === RBLX Operator setup ===
echo.

where node >nul 2>&1
if errorlevel 1 (
    echo [setup] Node.js was not found - the verify gate needs it.
    echo         Attempting an automatic install via winget...
    echo.
    winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements
    where node >nul 2>&1
    if errorlevel 1 if not exist "%ProgramFiles%\nodejs\node.exe" if not exist "%LOCALAPPDATA%\Programs\nodejs\node.exe" (
        echo.
        echo [setup] Automatic install did not take effect yet.
        echo         Install Node.js LTS from https://nodejs.org, then RE-RUN this file
        echo         (open a new window if this one was started before the install).
        pause
        exit /b 1
    )
    echo [setup] Node.js is installed, but this window has an outdated PATH.
    echo         Close it, open a NEW window, and re-run this file.
    pause
    exit /b 0
)

echo [setup] Running the verification gate (Luau + JS)...
call node pipeline/bridge.js verify
if errorlevel 1 (
    echo.
    echo [setup] Verify FAILED. Fix the reported issues, then re-run.
    pause
    exit /b 1
)
echo [setup] Verify PASSED.
echo.

echo What do you want to do?
echo   1 - Push to GitHub   (installs Git + gh, links your account, creates the repo, pushes)
echo   2 - Add to Studio    (installs Rojo, builds RBLXOperator.rbxl)
echo   3 - Open the desktop app  (RBLX Operator Studio .exe, if built)
echo.
set /p CHOICE=Enter 1, 2 or 3, then press Enter: 
if "%CHOICE%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0push.ps1"
if "%CHOICE%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0studio.ps1"
if "%CHOICE%"=="3" goto :app
if not defined CHOICE (
    echo [setup] No selection entered - re-run and type 1, 2 or 3.
    goto :end
)
goto :end

:app
echo [setup] Looking for a built copy of the desktop app...
set FOUND=
for /f "delims=" %%f in ('dir /b /s "app\dist\*.exe" 2^>nul') do set "FOUND=%%f"
if defined FOUND (
    echo [setup] Launching: %FOUND%
    start "" "%FOUND%"
) else (
    echo [setup] The desktop app is not built yet. Build it once with:
    echo         npm run app:install
    echo         npm run app:build
    echo.
    echo         (Output lands in app\dist\ - installer + portable .exe.)
    echo         Then re-run this file and choose 3.
    echo.
    echo         Or download a ready-made .exe from your repo's GitHub Actions
    echo         'Build EXE' workflow (Artifacts) after you push.
)
goto :end

:end
echo.
pause
