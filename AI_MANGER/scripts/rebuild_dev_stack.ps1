<# 
rebuild_dev_stack.ps1
Purpose:
  Centralize your developer CLIs in C:\Tools (or a custom root), optionally uninstall prior
  user-level installs, reinstall everything in a consistent way, and fix PATH ordering.

Usage:
  pwsh -ExecutionPolicy Bypass -File .\rebuild_dev_stack.ps1 -UninstallFirst
  pwsh -ExecutionPolicy Bypass -File .\rebuild_dev_stack.ps1

Notes:
  - Designed for Windows + PowerShell 7.
  - Runs idempotently. Re-run safely after changing lists/paths.
  - You may need a NEW terminal after it completes for PATH changes to take effect.
#>

[CmdletBinding()]
param(
  [switch]$UninstallFirst,

  # Change this if you want a different tools root
  [string]$ToolsRoot = "C:\Tools"
)

# ---------- Helper: console + exec ----------
function Write-Info($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "✔ $msg"  -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "⚠ $msg"  -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "✖ $msg"  -ForegroundColor Red }

function Invoke-Cmd($cmd, [switch]$IgnoreError) {
  Write-Host "  $cmd" -ForegroundColor DarkGray
  try {
    $global:LASTEXITCODE = 0
    & cmd /c $cmd
    if (-not $IgnoreError -and $LASTEXITCODE -ne 0) {
      throw "Command failed ($LASTEXITCODE)"
    }
  } catch {
    if (-not $IgnoreError) { throw }
  }
}

# ---------- Centralized locations ----------
$Paths = @{
  PipxHome   = Join-Path $ToolsRoot 'pipx\home'
  PipxBin    = Join-Path $ToolsRoot 'pipx\bin'
  NodePrefix = Join-Path $ToolsRoot 'node'
  NpmBin     = Join-Path $ToolsRoot 'node\npm'
  PnpmHome   = Join-Path $ToolsRoot 'pnpm\bin'
  PnpmStore  = Join-Path $ToolsRoot 'pnpm\store'
  RustupHome = Join-Path $ToolsRoot 'rustup'
  CargoHome  = Join-Path $ToolsRoot 'cargo'
  GoPath     = Join-Path $ToolsRoot 'go'
}

# ---------- Create directories ----------
Write-Info "Creating central directories under $ToolsRoot"
$Paths.GetEnumerator() | ForEach-Object {
  $null = New-Item -ItemType Directory -Path $_.Value -Force -ErrorAction SilentlyContinue
}

# ---------- Persistent env helpers ----------
function Set-UserEnv($Name, $Value) {
  [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
  $env:$Name = $Value  # also set for this session
  Write-Ok "$Name = $Value"
}

# ---------- PATH de-dupe and front-load ----------
function Prepend-PathIfMissing($p) {
  $expanded = [Environment]::ExpandEnvironmentVariables($p)
  $current  = [Environment]::GetEnvironmentVariable('Path','User')
  if (-not $current) { $current = "" }
  $sep = ';'
  $parts = $current -split ';' | Where-Object { $_ -ne '' } | Select-Object -Unique
  if ($parts -notcontains $expanded) {
    $newPath = "$expanded" + ($sep + ($parts -join $sep)).TrimEnd($sep)
  } else {
    # move to front
    $newPath = $expanded + $sep + ($parts | Where-Object { $_ -ne $expanded } -join $sep)
  }
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  $env:Path = "$newPath;" + [Environment]::GetEnvironmentVariable('Path','Machine')
}

Write-Info "Setting persistent environment variables (User scope)"
Set-UserEnv 'PIPX_HOME'            $Paths.PipxHome
Set-UserEnv 'PIPX_BIN_DIR'         $Paths.PipxBin
Set-UserEnv 'PIPX_DEFAULT_PYTHON'  'py -3.12'
Set-UserEnv 'PNPM_HOME'            $Paths.PnpmHome
Set-UserEnv 'RUSTUP_HOME'          $Paths.RustupHome
Set-UserEnv 'CARGO_HOME'           $Paths.CargoHome
Set-UserEnv 'GOPATH'               $Paths.GoPath

# Front-load PATH with our shims/bin dirs
Write-Info "Front-loading PATH (User) for centralized bins"
Prepend-PathIfMissing $Paths.PipxBin
Prepend-PathIfMissing $Paths.PnpmHome
Prepend-PathIfMissing $Paths.NpmBin
Prepend-PathIfMissing (Join-Path $Paths.GoPath 'bin')
Prepend-PathIfMissing (Join-Path $Paths.CargoHome 'bin')

Write-Info "Ensuring pipx and pnpm initial setup"
# Install/upgrade pipx (user level)
try {
  Invoke-Cmd 'py -3 -m pip install --user --upgrade pip pipx' -IgnoreError:$false
} catch {
  Write-Warn "pipx install via pip failed. Continuing (pipx might already exist)."
}
# ensure path for pipx
Invoke-Cmd 'pipx ensurepath' -IgnoreError

# Install/upgrade pnpm via npm (falls back to already installed)
Invoke-Cmd 'npm install -g pnpm' -IgnoreError

# Make npm use centralized prefix
Write-Info "Setting npm global prefix to $($Paths.NodePrefix)"
Invoke-Cmd "npm config set prefix `"$($Paths.NodePrefix)`" --global"

# Configure pnpm store-dir (to keep global cache under ToolsRoot)
Write-Info "Configuring pnpm store-dir to $($Paths.PnpmStore)"
Invoke-Cmd "pnpm config set store-dir `"$($Paths.PnpmStore)`"" -IgnoreError

# ---------- Desired system packages via winget ----------
$WingetIds = @(
  'Git.Git',
  'Python.Python.3.12',
  'OpenJS.NodeJS',
  'GitHub.cli',
  'Microsoft.PowerShell'
)
Write-Info "Installing/upgrading system packages via winget"
foreach ($id in $WingetIds) {
  Invoke-Cmd "winget install --id $id -e --source winget --silent" -IgnoreError
  Invoke-Cmd "winget upgrade  --id $id -e --source winget --silent" -IgnoreError
}

# ---------- Lists of apps to (optionally) uninstall then install ----------
$PipxApps = @(
  'invoke',          # for running tasks.py
  'aider-chat',
  'ruff',
  'black',
  'isort',
  'pylint',
  'mypy',
  'pyright',
  'pytest',
  'nox',
  'pre-commit',
  'uv',
  'langgraph-cli'
)

$NpmGlobal = @(
  '@google/generative-ai-cli',   # Gemini CLI
  '@anthropic-ai/claude-code',   # Claude Code CLI
  '@specifyapp/cli',             # Specify
  '@google/jules',               # Jules
  'eslint',
  'prettier'
)

# Copilot CLI (try new name, then old)
$CopilotPkgs = @('github-copilot-cli','@githubnext/github-copilot-cli')

# ---------- Optional: remove existing user-level installs ----------
if ($UninstallFirst) {
  Write-Info "UninstallFirst requested – removing existing pipx and npm globals"

  foreach ($pkg in $PipxApps) {
    Invoke-Cmd "pipx uninstall $pkg" -IgnoreError
  }
  foreach ($pkg in $NpmGlobal) {
    Invoke-Cmd "npm uninstall -g $pkg" -IgnoreError
  }
  foreach ($pkg in $CopilotPkgs) {
    Invoke-Cmd "npm uninstall -g $pkg" -IgnoreError
  }
}

# ---------- Install pipx apps ----------
Write-Info "Installing/Updating pipx apps"
foreach ($pkg in $PipxApps) {
  Invoke-Cmd "pipx install $pkg --force" -IgnoreError
}

# ---------- Install npm globals ----------
Write-Info "Installing/Updating npm global CLIs (centralized prefix)"
foreach ($pkg in $NpmGlobal) {
  Invoke-Cmd "npm install -g $pkg" -IgnoreError
}

# Copilot CLI with fallback
Write-Info "Installing GitHub Copilot CLI (try official, then legacy)"
$installedCopilot = $false
foreach ($pkg in $CopilotPkgs) {
  try {
    Invoke-Cmd "npm install -g $pkg"
    $installedCopilot = $true
    break
  } catch {
    Write-Warn "Failed to install $pkg"
  }
}
if (-not $installedCopilot) {
  Write-Warn "Copilot CLI failed to install via npm. Install manually if needed."
}

# ---------- Verify key commands ----------
$VerifyCmds = @(
  'git --version',
  'py -3.12 --version',
  'node --version',
  'gh --version',
  'pwsh --version',
  'pipx --version',
  'pnpm --version',
  'aider --version',
  'ruff --version',
  'black --version',
  'langgraph --version',
  'gemini --version',
  'claude-code --version',
  'copilot --version'
)

Write-Info "Verification (non-fatal)"
foreach ($cmd in $VerifyCmds) {
  Invoke-Cmd $cmd -IgnoreError
}

Write-Ok "Completed. Open a NEW terminal so PATH/environment updates take effect."
Write-Info "Central bins now live at:"
Write-Host "  $($Paths.PipxBin)"
Write-Host "  $($Paths.PnpmHome)"
Write-Host "  $($Paths.NpmBin)"
Write-Info "Tip: run 'invoke check' from your repo to validate the environment."
