# ============================================================================
#  RBLX Operator - one-click GitHub push (PowerShell)
#  Installs Git if needed, runs the verify gate, commits everything, creates
#  the GitHub repo, and pushes. Safe by default: refuses to push if your
#  secrets (.env) would be committed.
#
#  Usage:
#    .\scripts\push.ps1                                # auto: gh CLI or prompt
#    .\scripts\push.ps1 -RepoName my-operator          # custom repo name
#    .\scripts\push.ps1 -RepoUrl https://github.com/you/rblx-operator.git
#    .\scripts\push.ps1 -Private                       # private GitHub repo
# ============================================================================
param(
    [string]$RepoName = "RBLX_OPERATOR-",
    [string]$RepoUrl = "",
    [switch]$Private,
    [switch]$Auto,        # non-interactive: used by the desktop app (no Read-Host)
    [switch]$SkipVerify   # used by the desktop app, which already ran the gate
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host ""
Write-Host "=== RBLX Operator: GitHub push ===" -ForegroundColor Cyan

# --- 1. Node.js (needed for the verify gate) --------------------------------
# The desktop app bundles its own Node and passes -SkipVerify, so a machine
# without system Node can still push.
if (-not $SkipVerify -and -not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "[push] Node.js not found. Install from https://nodejs.org, then re-run." -ForegroundColor Red
    exit 1
}

# --- 2. Git: install via winget if missing -----------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "[push] winget was not found — install Git for Windows manually from https://git-scm.com, then re-run." -ForegroundColor Red
        exit 1
    }
    Write-Host "[push] Git not found. Installing Git for Windows (this takes a minute)..." -ForegroundColor Yellow
    winget install --id Git.Git -e --source winget `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[push] Git install failed. Install it manually from https://git-scm.com, then re-run." -ForegroundColor Red
        exit 1
    }
    # Refresh PATH from machine + user scopes so git is usable in this session.
    # Merge (not replace) so session-scoped entries like a version manager's
    # node path survive — the verify gate below still needs node.
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$env:Path;$machine;$user"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "[push] Git installed but PATH is not refreshed. Close this window, open a new one, re-run." -ForegroundColor Red
        exit 1
    }
    Write-Host "[push] Git installed." -ForegroundColor Green
}

# --- 3. Secrets safety check --------------------------------------------------
if (Test-Path "$Root\.env") {
    Write-Host "[push] Note: .env exists locally - it is gitignored, so it will NOT be pushed. Your keys stay on this machine." -ForegroundColor Yellow
}

# --- 4. Verify gate -----------------------------------------------------------
if ($SkipVerify) {
    Write-Host "[push] Verify gate skipped (-SkipVerify) - the desktop app already ran it with its bundled runtime." -ForegroundColor Yellow
}
else {
    Write-Host "[push] Running the verification gate: node pipeline/bridge.js verify"
    node pipeline/bridge.js verify
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[push] Verify FAILED - fix the reported issues before pushing." -ForegroundColor Red
        exit 1
    }
    Write-Host "[push] Verify PASSED." -ForegroundColor Green
}

# --- 5. Initialize + commit ----------------------------------------------------
if (-not (Test-Path "$Root\.git")) {
    git init | Out-Null
}
git branch -M main

if (-not (git config user.name)) {
    git config user.name "RBLX Operator"
    git config user.email "operator@roblox-operator.local"
    Write-Host "[push] Git identity not set - used a neutral 'RBLX Operator' identity." -ForegroundColor Yellow
    Write-Host "       Set your own later with:  git config user.name \"You\" / git config user.email \"you@x.com\""
}

if (git status --porcelain) {
    git add -A
    git commit -m "RBLX Operator: prompt-to-Roblox-game engine (MIT)"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[push] Commit failed. Fix the reported error, then re-run." -ForegroundColor Red
        exit 1
    }
    Write-Host "[push] Committed." -ForegroundColor Green
} else {
    Write-Host "[push] Nothing to commit - working tree already clean." -ForegroundColor Green
}

# --- 6. Safety: never commit secrets ------------------------------------------
$tracked = git ls-files
if ($tracked -match "\.env$") {
    Write-Host "[push] SECURITY ABORT: .env is tracked by git. Remove it with:  git rm --cached .env  then re-run." -ForegroundColor Red
    exit 1
}

# --- 7. GitHub: link account, create repo, push --------------------------------
function Test-RemoteOrigin { git remote | Select-String -Quiet "^origin$" }

# Make sure the GitHub CLI exists (it is what links your account to the repo)
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "[push] GitHub CLI not found - installing via winget..." -ForegroundColor Yellow
        winget install --id GitHub.cli -e --source winget `
            --accept-package-agreements --accept-source-agreements
        $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $user = [Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$env:Path;$machine;$user"
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "[push] GitHub CLI is not available (winget install GitHub.cli, or https://cli.github.com)." -ForegroundColor Red
        Write-Host "       The push can still work: create an empty repo at https://github.com/new" -ForegroundColor Yellow
        Write-Host "       (name it '$RepoName') and paste its URL when asked below." -ForegroundColor Yellow
    }
}

if (-not (Test-RemoteOrigin)) {
    if ($RepoUrl) {
        git remote add origin $RepoUrl
    }
    elseif (Get-Command gh -ErrorAction SilentlyContinue) {
        gh auth status 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            # --- THE one-time manual step: link the account (browser + code) ---
            Write-Host ""
            Write-Host "=== LINK YOUR GITHUB ACCOUNT ===" -ForegroundColor Cyan
            Write-Host "A browser will open with a one-time code. Log in, then paste the code back here." -ForegroundColor Cyan
            Write-Host ""
            if ($Auto) {
                # Desktop app: no interactive input - run the device flow; gh
                # prints the code + opens the browser, then polls until done.
                gh auth login --hostname github.com --git-protocol https --web
            }
            else {
                # Same flow from a terminal - also fully automatic (no prompts).
                gh auth login --hostname github.com --git-protocol https --web
            }
            gh auth status 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[push] GitHub login was not completed." -ForegroundColor Red
                Write-Host "       Re-run this script, or in any terminal run:  gh auth login" -ForegroundColor Yellow
                if ($Auto) {
                    Write-Host "       (In the desktop app, use the 'Link GitHub account' button, then push again.)" -ForegroundColor Yellow
                    exit 1
                }
            }
        }
        if ($LASTEXITCODE -eq 0) {
            $vis = if ($Private) { "--private" } else { "--public" }
            # The repo may already exist (created on github.com/new, or by a
            # previous push) — link to it instead of failing on create.
            $existing = gh repo view $RepoName --json url -q .url 2>$null
            if ($LASTEXITCODE -eq 0 -and $existing) {
                Write-Host "[push] Repo '$RepoName' already exists — linking origin to: $existing" -ForegroundColor Yellow
                git remote add origin $existing
            }
            else {
                Write-Host "[push] Creating GitHub repo '$RepoName' and pushing..." -ForegroundColor Cyan
                gh repo create $RepoName $vis --source $Root --remote origin --push
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "[push] Repo creation failed - the name may already exist on your account." -ForegroundColor Red
                    Write-Host "       Use -RepoName <other>, or create the repo at github.com/new and pass -RepoUrl." -ForegroundColor Yellow
                    exit 1
                }
                $login = gh api user -q .login
                Write-Host ""
                Write-Host "[push] Done! Repo live at: https://github.com/$login/$RepoName" -ForegroundColor Green
                exit 0
            }
        }
    }

    # Fallback: an existing empty repo URL. Without gh this still links you:
    # the first push opens a browser sign-in via Git Credential Manager.
    if (-not (Test-RemoteOrigin)) {
        if ($Auto) {
            Write-Host "[push] No authenticated GitHub CLI and interactive input is unavailable here." -ForegroundColor Yellow
            Write-Host "       In the desktop app: use the 'Link GitHub account' button first, then push again." -ForegroundColor Yellow
            Write-Host "       In a terminal: create a repo at https://github.com/new and run:" -ForegroundColor Yellow
            Write-Host "         scripts\push.ps1 -RepoUrl https://github.com/<you>/$RepoName.git" -ForegroundColor Yellow
            exit 1
        }
        $url = Read-Host "Empty GitHub repo URL (create one at https://github.com/new, name it '$RepoName'). Press Enter to skip"
        if ($url) {
            git remote add origin $url
        }
        else {
            Write-Host "[push] Skipped. Push later with:  git remote add origin <url>  then  git push -u origin main" -ForegroundColor Yellow
            exit 0
        }
    }
}

Write-Host "[push] Pushing - if a browser sign-in opens (Git Credential Manager), that is the account link. Complete it." -ForegroundColor Cyan
git push -u origin main
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "[push] PUSHED to origin/main. CI will run the full verify + smoke test automatically." -ForegroundColor Green
} else {
    Write-Host "[push] Push failed - check the error above (auth, network, or remote name)." -ForegroundColor Red
}
