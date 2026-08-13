@echo off
REM ============================================================================
REM  RBLX Operator - one-click setup (Windows)
REM  Double-click this file. It verifies the repo, then lets you choose:
REM    1) Push to GitHub     (installs Git + GitHub CLI, links your account,
REM                           creates the repo, pushes)
REM    2) Add to Studio      (installs Rojo if needed, builds the .rbxl)
REM    3) Design a game      (type an idea, the engine ships the game)
REM    4) Print the banner   (BUILDER BOI says hi)
REM  This window NEVER closes silently - every message ends with a pause.
REM ============================================================================
setlocal
cd /d "%~dp0.."

echo.
echo === RBLX Operator setup ===
echo.

where node >nul 2>&1
if errorlevel 1 (
    echo [setup] Node.js was not found - the engine needs it.
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
echo   3 - Design a game    (type an idea - the rblx-designer agent ships it)
echo   4 - Print the banner (BUILDER BOI says hi)
echo.
set /p CHOICE=Enter 1, 2, 3 or 4, then press Enter: 
if "%CHOICE%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0push.ps1"
if "%CHOICE%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0studio.ps1"
if "%CHOICE%"=="3" goto :design
if "%CHOICE%"=="4" (
    node pipeline/bridge.js banner
    goto :end
)
if not defined CHOICE (
    echo [setup] No selection entered - re-run and type 1, 2, 3 or 4.
    goto :end
)
goto :end

:design
echo.
echo [setup] Describe a game - anything. Example:
echo         a dark zombie survival in a cursed mall, 10 waves
echo.
set /p IDEA=Game idea: 
if not defined IDEA (
    echo [setup] No idea entered - skipping.
    goto :end
)
echo.
echo [setup] Designing: %IDEA%
echo         This uses the rblx-designer agent (opencode). If opencode or a
echo         model isn't configured yet, it falls back to offline derivation
echo         (zero keys, zero accounts).
call node pipeline/bridge.js design "%IDEA%"
if errorlevel 1 (
    echo.
    echo [setup] Design via opencode needs setup - trying zero-key offline mode...
    call node pipeline/bridge.js newgame --offline "%IDEA%"
)
echo.
echo [setup] Next: open a terminal and run:
echo         rojo build default.project.json -o RBLXOperator.rbxl
echo         then open RBLXOperator.rbxl in Roblox Studio and press Play.
goto :end

:end
echo.
pause
