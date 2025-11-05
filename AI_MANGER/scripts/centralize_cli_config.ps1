<# 
centralize_cli_config.ps1
Goal: Stop "config folders" from popping up in every project by routing configs/caches/data
to a few centralized locations, while keeping CLIs globally installed.

What it does (User scope):
  - Sets XDG_* vars to C:\Tools\{config,cache,data}
  - Centralizes caches for common tools (pip, npm, pnpm, ruff, black, mypy, uv)
  - Leaves binaries where your rebuild script put them (pipx, npm -g, pnpm)
  - (Optional) Generates wrapper shims in C:\Tools\bin for CLIs that need custom flags/env

Usage:
  pwsh -ExecutionPolicy Bypass -File .\centralize_cli_config.ps1
  pwsh -ExecutionPolicy Bypass -File .\centralize_cli_config.ps1 -BuildWrappers

Open a NEW terminal afterwards.
#>

[CmdletBinding()]
param(
  [switch]$BuildWrappers,

  [string]$Root = "C:\Tools"
)

function Say($s, $c="Cyan") { Write-Host "==> $s" -ForegroundColor $c }
function Ok($s) { Write-Host "✔ $s" -ForegroundColor Green }

# --- Layout ---
$CFG   = Join-Path $Root 'config'
$CACHE = Join-Path $Root 'cache'
$DATA  = Join-Path $Root 'data'
$BIN   = Join-Path $Root 'bin'

$Dirs = @($CFG, $CACHE, $DATA, $BIN,
  Join-Path $CACHE 'pip',
  Join-Path $CACHE 'npm',
  Join-Path $CACHE 'pnpm',
  Join-Path $CACHE 'ruff',
  Join-Path $CACHE 'black',
  Join-Path $CACHE 'mypy',
  Join-Path $CACHE 'uv'
)

$Dirs | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

# --- Persist env (User scope) ---
function Set-UserEnv($k,$v) {
  [Environment]::SetEnvironmentVariable($k,$v,'User')
  $env:$k = $v
  Ok "$k=$v"
}

Say "Setting XDG base dirs (many cross-platform tools honor these)"
Set-UserEnv XDG_CONFIG_HOME $CFG
Set-UserEnv XDG_CACHE_HOME  $CACHE
Set-UserEnv XDG_DATA_HOME   $DATA

Say "Common tool caches"
Set-UserEnv PIP_CACHE_DIR          (Join-Path $CACHE 'pip')
Set-UserEnv NPM_CONFIG_CACHE       (Join-Path $CACHE 'npm')
Set-UserEnv PNPM_HOME              "C:\Tools\pnpm\bin"   # keep consistent with rebuild script
Set-UserEnv RUFF_CACHE_DIR         (Join-Path $CACHE 'ruff')
Set-UserEnv BLACK_CACHE_DIR        (Join-Path $CACHE 'black')
Set-UserEnv MYPY_CACHE_DIR         (Join-Path $CACHE 'mypy')
Set-UserEnv UV_CACHE_DIR           (Join-Path $CACHE 'uv')
# Optional: centralize Python __pycache__ (keeps projects clean but changes Python default)
Set-UserEnv PYTHONPYCACHEPREFIX    (Join-Path $CACHE 'pyc')

Say "ESLint cache behavior (only used if --cache is on)"
Set-UserEnv ESLINT_CACHE           'true'
Set-UserEnv ESLINT_CACHE_LOCATION  (Join-Path $CACHE 'eslint')

# --- Optional wrappers: enforce flags/env for specific CLIs ---
if ($BuildWrappers) {
  Say "Building wrappers in $BIN (idempotent)"
  Get-ChildItem $BIN -Filter *.cmd -ErrorAction SilentlyContinue | Remove-Item -Force

  function New-Wrap($Name, $Body) {
    $path = Join-Path $BIN "${Name}.cmd"
    Set-Content -Encoding ASCII -Path $path -Value $Body
    Ok "wrapper: $path"
  }

  # Helper: call a real exe/cmd anywhere on PATH with our env
  $preamble = '@echo off
setlocal enableextensions enabledelayedexpansion
rem XDG & centralized caches
set "XDG_CONFIG_HOME={CFG}"
set "XDG_CACHE_HOME={CACHE}"
set "XDG_DATA_HOME={DATA}"
set "PIP_CACHE_DIR={CACHE}\pip"
set "RUFF_CACHE_DIR={CACHE}\ruff"
set "BLACK_CACHE_DIR={CACHE}\black"
set "MYPY_CACHE_DIR={CACHE}\mypy"
set "UV_CACHE_DIR={CACHE}\uv"
set "ESLINT_CACHE=true"
set "ESLINT_CACHE_LOCATION={CACHE}\eslint"
'

  $preamble = $preamble.Replace('{CFG}',$CFG).Replace('{CACHE}',$CACHE).Replace('{DATA}',$DATA)

  # Ruff
  New-Wrap 'ruff' ($preamble + 'ruff %*' + "`r`n" + 'exit /b %errorlevel%')
  # Black
  New-Wrap 'black' ($preamble + 'black %*' + "`r`n" + 'exit /b %errorlevel%')
  # Mypy
  New-Wrap 'mypy' ($preamble + 'mypy %*' + "`r`n" + 'exit /b %errorlevel%')
  # ESLint (ensure cache path)
  New-Wrap 'eslint' ($preamble + 'eslint --cache --cache-location "%ESLINT_CACHE_LOCATION%" %*' + "`r`n" + 'exit /b %errorlevel%')
  # Pyright (no cache flag; still gets XDG env)
  New-Wrap 'pyright' ($preamble + 'pyright %*' + "`r`n" + 'exit /b %errorlevel%')
  # Aider (pin config path if you keep one centrally)
  $aiderCfg = Join-Path $CFG 'aider\aider.conf.yml'
  New-Item -ItemType Directory -Force -Path (Split-Path $aiderCfg) | Out-Null
  if (-not (Test-Path $aiderCfg)) { Set-Content -Path $aiderCfg -Value "# global aider config" -Encoding UTF8 }
  New-Wrap 'aider' ($preamble + 'aider --config "'+$aiderCfg+'" %*' + "`r`n" + 'exit /b %errorlevel%')
  # Prettier (no cache, but keeps env)
  New-Wrap 'prettier' ($preamble + 'prettier %*' + "`r`n" + 'exit /b %errorlevel%')
  # Copilot/Gemini/Claude (pass-through with XDG env)
  New-Wrap 'copilot' ($preamble + 'copilot %*' + "`r`n" + 'exit /b %errorlevel%')
  New-Wrap 'gemini'  ($preamble + 'gemini %*'  + "`r`n" + 'exit /b %errorlevel%')
  New-Wrap 'claude-code' ($preamble + 'claude-code %*' + "`r`n" + 'exit /b %errorlevel%')

  # Put master bin first in User PATH (front-load)
  $uPath = [Environment]::GetEnvironmentVariable('Path','User')
  if ($null -eq $uPath) { $uPath = "" }
  if (-not ($uPath -split ';' | Where-Object { $_ -eq $BIN })) {
    [Environment]::SetEnvironmentVariable('Path', "$BIN;$uPath", 'User')
  }
  Ok "Wrappers ready. Add only $BIN to the front of PATH for clean launches."
}

Ok "Centralization complete. Open a NEW terminal to apply settings."
