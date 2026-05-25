# setup-dev-env.ps1
# Windows Development Environment Setup Script
#
# Installs and configures:
#   - Git for Windows
#   - Claude Code (with PATH fix)
#   - Docker Desktop (includes docker compose)
#   - Claude login (pauses for manual browser auth)
#
# Usage:
#   PowerShell: .\setup-dev-env.ps1
#   Skip Docker: .\setup-dev-env.ps1 -SkipDocker

param(
    [switch]$SkipDocker
)

$ErrorActionPreference = "Continue"

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Step([string]$n, [string]$msg) {
    Write-Host ""
    Write-Host "[$n] $msg" -ForegroundColor Cyan
    Write-Host ("-" * 50) -ForegroundColor DarkGray
}

function Refresh-EnvPath {
    $machine = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$machine;$user"
}

function Test-Command([string]$cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

# ── Admin check ───────────────────────────────────────────────────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "[WARN] Not running as Administrator. Some installations may fail." -ForegroundColor Yellow
    Write-Host "       Recommend: right-click PowerShell > Run as Administrator" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "    Development Environment Setup               " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# ── Step 1: Git ───────────────────────────────────────────────────────────────

Write-Step "1/4" "Installing Git for Windows"

if (Test-Command "git") {
    Write-Host "Git already installed: $(git --version)" -ForegroundColor Green
} else {
    winget install --id Git.Git -e --source winget `
        --accept-package-agreements --accept-source-agreements --silent
    Refresh-EnvPath
    if (Test-Command "git") {
        Write-Host "Git installed: $(git --version)" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Git not found after install. Restart terminal if needed." -ForegroundColor Yellow
    }
}

# ── Step 2: Claude Code ───────────────────────────────────────────────────────

Write-Step "2/4" "Installing Claude Code"

Write-Host "Running Claude Code PowerShell installer..."
irm https://claude.ai/install.ps1 | iex

# ── Step 3: PATH for Claude Code ─────────────────────────────────────────────

Write-Step "3/4" "Configuring PATH for Claude Code"

$claudeDir = "$env:USERPROFILE\.local\bin"
$userPath  = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($null -eq $userPath) { $userPath = "" }

if ($userPath -notlike "*$claudeDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$userPath;$claudeDir", "User")
    Write-Host "Added to User PATH: $claudeDir" -ForegroundColor Green
} else {
    Write-Host "PATH already contains: $claudeDir" -ForegroundColor Green
}

# Apply immediately in this session
Refresh-EnvPath

# Verify
$claudeExe = "$claudeDir\claude.exe"
if (Test-Path $claudeExe) {
    $ver = & $claudeExe --version 2>&1
    Write-Host "Claude Code ready: $ver" -ForegroundColor Green
} else {
    Write-Host "[WARN] claude.exe not found at $claudeExe" -ForegroundColor Yellow
    Write-Host "       Try restarting PowerShell after setup completes." -ForegroundColor Yellow
}

# ── Step 4: Docker Desktop (includes docker compose) ─────────────────────────

if ($SkipDocker) {
    Write-Host ""
    Write-Host "[4/4] Docker installation skipped (-SkipDocker)" -ForegroundColor Yellow
} else {
    Write-Step "4/4" "Installing Docker Desktop (includes docker compose)"

    if (Test-Command "docker") {
        Write-Host "Docker already installed: $(docker --version)" -ForegroundColor Green
    } else {
        # Enable WSL2 features required by Docker Desktop
        Write-Host "Enabling WSL2 and Hyper-V features (may require restart)..."
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart 2>&1 | Out-Null
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart 2>&1 | Out-Null

        winget install --id Docker.DockerDesktop -e --source winget `
            --accept-package-agreements --accept-source-agreements
        Refresh-EnvPath

        if (Test-Command "docker") {
            Write-Host "Docker Desktop installed: $(docker --version)" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Docker not found in PATH yet." -ForegroundColor Yellow
            Write-Host "       Start Docker Desktop and restart terminal if 'docker compose' fails." -ForegroundColor Yellow
        }
    }

    # Start Docker Desktop daemon if installed but not running
    $dockerDesktopExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if ((Test-Path $dockerDesktopExe) -and (-not (Get-Process "Docker Desktop" -ErrorAction SilentlyContinue))) {
        Write-Host "Starting Docker Desktop daemon..." -ForegroundColor Yellow
        Start-Process $dockerDesktopExe -WindowStyle Minimized
        Write-Host "Docker Desktop starting in background (takes ~30 seconds)." -ForegroundColor Yellow
    }
}

# ── Step 5: Claude Login ──────────────────────────────────────────────────────

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "    Claude Code Login                           " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "A browser window will open for authentication." -ForegroundColor Yellow
Write-Host "Complete the sign-in, then return to this terminal." -ForegroundColor Yellow
Write-Host "If the browser does not open, press 'c' to copy the login URL." -ForegroundColor Yellow
Write-Host ""

if (Test-Path $claudeExe) {
    & $claudeExe auth login
} elseif (Test-Command "claude") {
    claude auth login
} else {
    Write-Host "[ERROR] claude.exe not found. Open a new terminal and run: claude auth login" -ForegroundColor Red
}

# ── Done ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "    Setup Complete!                             " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Verify your tools:" -ForegroundColor Cyan
Write-Host "  git --version" -ForegroundColor White
Write-Host "  claude --version" -ForegroundColor White
Write-Host "  docker --version" -ForegroundColor White
Write-Host "  docker compose version" -ForegroundColor White
Write-Host ""
Write-Host "Notes:" -ForegroundColor Yellow
Write-Host "  - If 'docker compose' fails, wait for Docker Desktop to finish starting." -ForegroundColor Yellow
Write-Host "  - If PATH changes aren't picked up, open a new PowerShell window." -ForegroundColor Yellow
Write-Host "  - Docker Desktop requires WSL2 or Hyper-V. A restart may be needed on first run." -ForegroundColor Yellow
