# ============================================================================
#  RBLX Operator - build & install the Studio Craft plugin
#  Installs Rojo (via Rokit) if needed, builds plugin/RBLXOperatorCraft.rbxmx,
#  and copies it into the Studio Plugins folder. Restart Studio to load it.
#
#  Usage:
#    .\scripts\plugin.ps1
# ============================================================================
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host ""
Write-Host "=== RBLX Operator: build & install Craft plugin ===" -ForegroundColor Cyan

# --- 1. Rojo: install via Rokit if missing -----------------------------------
if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
    Write-Host "[plugin] Rojo not found. Installing Rokit (Roblox toolchain manager) + Rojo..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    try {
        Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
    } catch {
        Write-Host "[plugin] Rokit install failed: $_" -ForegroundColor Red
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
    }
    rokit add rojo-rbx/rojo | Out-Null
    rokit install --yes 2>$null | Out-Null
    if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
        Write-Host "[plugin] Rojo installed but not on PATH in this session. Close and reopen the terminal, then re-run." -ForegroundColor Red
        exit 1
    }
    Write-Host "[plugin] Rojo installed." -ForegroundColor Green
}

# --- 2. Build the plugin model ------------------------------------------------
Write-Host "[plugin] Building plugin\plugin.project.json -> RBLXOperatorCraft.rbxmx ..."
rojo build plugin/plugin.project.json -o plugin/build/RBLXOperatorCraft.rbxmx
if ($LASTEXITCODE -ne 0) {
    Write-Host "[plugin] Build FAILED. Fix the reported issues, then re-run." -ForegroundColor Red
    exit 1
}

# --- 3. Install into Studio's Plugins folder ----------------------------------
$PluginsDir = "$env:LOCALAPPDATA\Roblox\Plugins"
if (-not (Test-Path $PluginsDir)) {
    Write-Host "[plugin] Plugins folder not found at $PluginsDir" -ForegroundColor Yellow
    Write-Host "         Studio may not have run yet, or it's installed elsewhere." -ForegroundColor Yellow
    Write-Host "         Copy the built file manually to your Studio Plugins folder:" -ForegroundColor Yellow
    Write-Host "           plugin\build\RBLXOperatorCraft.rbxmx" -ForegroundColor Yellow
    exit 0
}
Copy-Item "plugin\build\RBLXOperatorCraft.rbxmx" "$PluginsDir\RBLXOperatorCraft.rbxmx" -Force
Write-Host ""
Write-Host "[plugin] Installed -> $PluginsDir\RBLXOperatorCraft.rbxmx" -ForegroundColor Green
Write-Host "        Restart Roblox Studio, then use the 'RBLX Operator' toolbar button" -ForegroundColor Cyan
Write-Host "        (or Plugins menu). CONSOLE / PLAYTEST / CRAFT / SPEC." -ForegroundColor Cyan
