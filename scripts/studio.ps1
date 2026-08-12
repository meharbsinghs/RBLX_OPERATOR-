# ============================================================================
#  RBLX Operator - one-click "add to Studio" (PowerShell)
#  Installs Rojo (via Rokit, the Roblox toolchain manager) if needed, builds
#  the .rbxl place file from this repo, and prints how to live-sync and how
#  to auto-upload generated assets through Roblox Open Cloud.
#
#  Usage:
#    .\scripts\studio.ps1        # build RBLXOperator.rbxl
#    .\scripts\studio.ps1 -Serve # build, then print live-sync steps
# ============================================================================
param([switch]$Serve)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host ""
Write-Host "=== RBLX Operator: add to Studio ===" -ForegroundColor Cyan

# --- 1. Node.js (used by the pipeline; cheap to check) -------------------------
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "[studio] Node.js not found. Install from https://nodejs.org, then re-run." -ForegroundColor Red
    exit 1
}

# --- 2. Rojo: install via Rokit if missing --------------------------------------
if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
    Write-Host "[studio] Rojo not found. Installing Rokit (Roblox toolchain manager) + Rojo..." -ForegroundColor Yellow
    Write-Host "        This fetches the official bootstrap from github.com/rojo-rbx/rokit." -ForegroundColor Yellow
    Write-Host "        It can take a minute on first run — the window will pause until it finishes." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    try {
        Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
    } catch {
        Write-Host "[studio] Rokit install failed: $_" -ForegroundColor Red
        Write-Host "         Install Rojo manually from https://rojo.space, then re-run." -ForegroundColor Yellow
        exit 1
    }
    $RokitDir = "$env:USERPROFILE\.rokit\bin"
    if ($env:PATH -notlike "*$RokitDir*") {
        $env:PATH = "$RokitDir;$env:PATH"
        [Environment]::SetEnvironmentVariable("PATH", "$RokitDir;" + [Environment]::GetEnvironmentVariable("PATH", "User"), "User")
    }
    if (-not (Test-Path "$Root\rokit.toml")) {
        rokit init --yes 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$Root\rokit.toml")) {
            Write-Host "[studio] Could not initialize the Rokit toolchain. Install Rojo manually from https://rojo.space, then re-run." -ForegroundColor Red
            exit 1
        }
    }
    rokit add rojo-rbx/rojo | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[studio] Could not add rojo to the toolchain. Install Rojo manually from https://rojo.space, then re-run." -ForegroundColor Red
        exit 1
    }
    rokit install --yes
    if ($LASTEXITCODE -ne 0) { rokit install | Out-Null }   # older rokit: no --yes flag
    if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
        Write-Host "[studio] Rojo installed but not on PATH in this session. Close and reopen the terminal, then re-run." -ForegroundColor Red
        exit 1
    }
    Write-Host "[studio] Rojo installed." -ForegroundColor Green
}

# --- 3. Build the place file ------------------------------------------------------
Write-Host "[studio] Building RBLXOperator.rbxl..."
rojo build default.project.json -o RBLXOperator.rbxl
if ($LASTEXITCODE -ne 0) {
    Write-Host "[studio] Build FAILED. Fix the reported issues, then re-run." -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "[studio] Built RBLXOperator.rbxl" -ForegroundColor Green
Write-Host "        Open it in Roblox Studio and press Play. That is the engine's reference game."
Write-Host "        Design your own first with:  node pipeline/bridge.js newgame \"<idea>\""

# --- 4. Live-sync + Open Cloud hints ----------------------------------------------
if ($Serve) {
    Write-Host ""
    Write-Host "Live editing (recommended while iterating):" -ForegroundColor Cyan
    Write-Host "  1. Install the Rojo Studio plugin: https://www.roblox.com/library/7168068472/Rojo"
    Write-Host "  2. Run:  rojo serve default.project.json"
    Write-Host "  3. In Studio: Plugins -> Rojo -> Connect. Edit Luau -> instant sync."
}
Write-Host ""
Write-Host "Auto-upload generated 3D models to Roblox (no manual importing):" -ForegroundColor Cyan
Write-Host "  1. Add OPEN_CLOUD_API_KEY=... to .env (create at create.roblox.com -> Credentials, scope: assets:write)"
Write-Host "  2. node pipeline/bridge.js asset \"low-poly zombie model\" --kind=enemy"
Write-Host "  3. The pipeline uploads the .glb and injects the live rbxassetid:// link."
