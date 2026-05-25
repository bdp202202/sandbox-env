# setup-dev-env.ps1
# Windows Development Environment Setup Script
#
# Installs and configures:
#   - Git for Windows
#   - Node.js LTS (required for npx)
#   - Claude Code (with PATH fix)
#   - Docker Desktop (includes docker compose)
#   - Claude login (pauses for manual browser auth)
#   - Claude plugins: superpowers, mattpocock/skills
#
# Package manager: winget (preferred) with Chocolatey as automatic fallback
#
# Usage:
#   PowerShell: .\setup-dev-env.ps1
#   Skip Docker: .\setup-dev-env.ps1 -SkipDocker
#   Custom browser: .\setup-dev-env.ps1 -BrowserPath "C:\Program Files\Google\Chrome\Application\chrome.exe"

param(
    [switch]$SkipDocker,
    [string]$BrowserPath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
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

# Install a package using winget if available, otherwise Chocolatey.
# $wingetId  : e.g. "Git.Git"
# $chocoName : e.g. "git"
# $wingetArgs: extra winget flags array (optional)
function Install-Package([string]$wingetId, [string]$chocoName, [string[]]$wingetArgs = @()) {
    if (Test-Command "winget") {
        Write-Host "  Using winget to install $wingetId..."
        $baseArgs = @("install", "--id", $wingetId, "-e", "--source", "winget",
                      "--accept-package-agreements", "--accept-source-agreements", "--silent")
        winget @($baseArgs + $wingetArgs)
    } elseif (Test-Command "choco") {
        Write-Host "  Using Chocolatey to install $chocoName..."
        choco install $chocoName -y --no-progress
    } else {
        Write-Host "[ERROR] Neither winget nor Chocolatey is available." -ForegroundColor Red
    }
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

# ── Package manager bootstrap ─────────────────────────────────────────────────

if (-not (Test-Command "winget")) {
    Write-Host ""
    Write-Host "[prep] winget not found — installing Chocolatey as package manager..." -ForegroundColor Yellow

    if (-not (Test-Command "choco")) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1'))
        Refresh-EnvPath
    }

    if (Test-Command "choco") {
        Write-Host "Chocolatey ready: $(choco --version)" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Could not install Chocolatey. Package installs may fail." -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "[prep] winget found: $(winget --version)" -ForegroundColor Green
}

# ── Step 1: Git ───────────────────────────────────────────────────────────────

Write-Step "1/5" "Installing Git for Windows"

if (Test-Command "git") {
    Write-Host "Git already installed: $(git --version)" -ForegroundColor Green
} else {
    Install-Package "Git.Git" "git"
    Refresh-EnvPath
    if (Test-Command "git") {
        Write-Host "Git installed: $(git --version)" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Git not found after install. Restart terminal if needed." -ForegroundColor Yellow
    }
}

# ── Step 2: Node.js LTS ───────────────────────────────────────────────────────

Write-Step "2/5" "Installing Node.js LTS (required for npx)"

if (Test-Command "node") {
    Write-Host "Node.js already installed: $(node --version)" -ForegroundColor Green
} else {
    Install-Package "OpenJS.NodeJS.LTS" "nodejs-lts"
    Refresh-EnvPath
    if (Test-Command "node") {
        Write-Host "Node.js installed: $(node --version), npm: $(npm --version)" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Node.js not found after install. Restart terminal if needed." -ForegroundColor Yellow
    }
}

# ── Step 3: Claude Code + PATH ────────────────────────────────────────────────

Write-Step "3/5" "Installing Claude Code"

Write-Host "Running Claude Code PowerShell installer..."
irm https://claude.ai/install.ps1 | iex

$claudeDir = "$env:USERPROFILE\.local\bin"
$userPath  = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($null -eq $userPath) { $userPath = "" }

if ($userPath -notlike "*$claudeDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$userPath;$claudeDir", "User")
    Write-Host "Added to User PATH: $claudeDir" -ForegroundColor Green
} else {
    Write-Host "PATH already contains: $claudeDir" -ForegroundColor Green
}

Refresh-EnvPath

$claudeExe = "$claudeDir\claude.exe"
if (Test-Path $claudeExe) {
    $ver = & $claudeExe --version 2>&1
    Write-Host "Claude Code ready: $ver" -ForegroundColor Green
} else {
    Write-Host "[WARN] claude.exe not found at $claudeExe" -ForegroundColor Yellow
    Write-Host "       Try restarting PowerShell after setup completes." -ForegroundColor Yellow
}

# ── Step 4: Docker ────────────────────────────────────────────────────────────

if ($SkipDocker) {
    Write-Host ""
    Write-Host "[4/5] Docker installation skipped (-SkipDocker)" -ForegroundColor Yellow
} else {
    Write-Step "4/5" "Installing Docker (includes docker compose)"

    # Detect Windows Server — Docker Desktop requires Windows 10/11 client OS
    $osCaption = (Get-WmiObject Win32_OperatingSystem).Caption
    $isWindowsServer = $osCaption -like "*Server*"

    if (Test-Command "docker") {
        Write-Host "Docker already installed: $(docker --version)" -ForegroundColor Green
    } elseif ($isWindowsServer) {
        Write-Host "  Windows Server detected ($osCaption)" -ForegroundColor Yellow
        Write-Host "  Installing Docker Engine via DockerMsftProvider (not Docker Desktop)..."

        # Install NuGet provider silently if needed
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null

        Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
        Install-Package -Name docker -ProviderName DockerMsftProvider -Force

        Refresh-EnvPath

        # Install Docker Compose V2 as a CLI plugin
        Write-Host "  Installing Docker Compose V2 plugin..."
        $composeDir = "$env:ProgramData\Docker\cli-plugins"
        New-Item -ItemType Directory -Force -Path $composeDir | Out-Null
        $composeUrl = "https://github.com/docker/compose/releases/latest/download/docker-compose-windows-x86_64.exe"
        Invoke-WebRequest -Uri $composeUrl -OutFile "$composeDir\docker-compose.exe" -UseBasicParsing

        Write-Host "Docker Engine installed." -ForegroundColor Green
        Write-Host "[WARN] A system RESTART is required to start the Docker service." -ForegroundColor Yellow
        Write-Host "       After restart, start Docker with: Start-Service docker" -ForegroundColor Yellow
    } else {
        Write-Host "  Windows client OS detected — installing Docker Desktop..."
        Write-Host "  Enabling WSL2 and Hyper-V features (may require restart)..."
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart 2>&1 | Out-Null
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart 2>&1 | Out-Null

        Install-Package "Docker.DockerDesktop" "docker-desktop"
        Refresh-EnvPath

        $dockerDesktopExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        if ((Test-Path $dockerDesktopExe) -and (-not (Get-Process "Docker Desktop" -ErrorAction SilentlyContinue))) {
            Write-Host "Starting Docker Desktop daemon in background..." -ForegroundColor Yellow
            Start-Process $dockerDesktopExe -WindowStyle Minimized
        }

        if (Test-Command "docker") {
            Write-Host "Docker Desktop installed: $(docker --version)" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Docker not found in PATH yet." -ForegroundColor Yellow
            Write-Host "       Start Docker Desktop and restart terminal if 'docker compose' fails." -ForegroundColor Yellow
        }
    }
}

# ── Step 5: Claude Login ──────────────────────────────────────────────────────

Write-Step "5/5" "Claude Code Login"

Write-Host "A browser window will open for authentication." -ForegroundColor Yellow
Write-Host "Complete the sign-in, then return to this terminal." -ForegroundColor Yellow
Write-Host "If the browser does not open, press 'c' to copy the login URL." -ForegroundColor Yellow
Write-Host ""

# Create a URL-fixing wrapper: Claude Code sometimes produces a malformed URL
# (http://"https//...) due to quote/path issues. The wrapper fixes the pattern
# before forwarding to Chrome.
$wrapperPath = "$env:TEMP\claude-chrome-wrapper.ps1"
Set-Content -Path $wrapperPath -Encoding UTF8 -Value @"
# Join all args in case the URL was split on quote characters
`$raw = (`$args -join '')
# Fix: http://"https//... or http://https//... -> https://...
`$url = `$raw -replace '^http://["`"]?https[/]+', 'https://'
# Remove any stray quotes
`$url = `$url -replace '["`"]', ''
# Ensure the URL starts with https://
if (`$url -notmatch '^https?://') { `$url = 'https://' + `$url }
Start-Process -FilePath '$BrowserPath' -ArgumentList `$url
"@

$env:BROWSER = "powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$wrapperPath`""
Write-Host "Browser wrapper created: $wrapperPath" -ForegroundColor Green

if (Test-Path $claudeExe) {
    & $claudeExe auth login
} elseif (Test-Command "claude") {
    claude auth login
} else {
    Write-Host "[ERROR] claude.exe not found. Open a new terminal and run: claude auth login" -ForegroundColor Red
}

# ── Post-login: Install Claude plugins & skills ───────────────────────────────

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "    Installing Plugins & Skills                 " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# superpower plugin
Write-Host ""
Write-Host "[plugin 1/2] Installing superpowers plugin..." -ForegroundColor Yellow
if (Test-Path $claudeExe) {
    & $claudeExe plugin install superpowers@claude-plugins-official
} elseif (Test-Command "claude") {
    claude plugin install superpowers@claude-plugins-official
} else {
    Write-Host "[SKIP] claude not found. Run manually: claude plugin install superpowers@claude-plugins-official" -ForegroundColor Yellow
}

# mattpocock skills (via npx)
Write-Host ""
Write-Host "[plugin 2/2] Installing mattpocock/skills via npx..." -ForegroundColor Yellow
if (Test-Command "npx") {
    npx skills@latest add mattpocock/skills
} else {
    Write-Host "[SKIP] npx not found. Restart terminal then run: npx skills@latest add mattpocock/skills" -ForegroundColor Yellow
}

# ── Done ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "    Setup Complete!                             " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Verify your tools:" -ForegroundColor Cyan
Write-Host "  git --version" -ForegroundColor White
Write-Host "  node --version  /  npx --version" -ForegroundColor White
Write-Host "  claude --version" -ForegroundColor White
Write-Host "  docker --version  /  docker compose version" -ForegroundColor White
Write-Host ""
Write-Host "Notes:" -ForegroundColor Yellow
Write-Host "  - If 'docker compose' fails, wait for Docker Desktop to finish starting (~30s)." -ForegroundColor Yellow
Write-Host "  - If PATH changes aren't picked up, open a new PowerShell window." -ForegroundColor Yellow
Write-Host "  - Docker Desktop requires WSL2 or Hyper-V. A restart may be needed on first run." -ForegroundColor Yellow
