# ModuleName: MasterBin
param()

function Get-SourceTag {
  param([string]$Path, [string[]]$Priority)
  foreach ($p in $Priority) {
    if ($Path -match [Regex]::Escape($p)) { return $p }
  }
  # fallback: folder name
  return (Split-Path $Path -Leaf)
}

function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  task MasterBin.Clean {
    $dest = $Context.MasterBin.Path
    if (Test-Path $dest) {
      Get-ChildItem $dest -Filter *.cmd -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
      Write-Host "Cleaned $dest" -ForegroundColor Green
    }
  }

  task MasterBin.Rebuild -Depends MasterBin.Clean {
    $cfg   = $Context.MasterBin
    if (-not $cfg.Enable) {
      Write-Host "MasterBin.Enable is false; skipping (enable in config to use)." -ForegroundColor Yellow
      return
    }

    $dest  = $cfg.Path
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }

    $deny  = @($cfg.DenyList)
    $prio  = @($cfg.Priority)
    $seen  = @{}

    # Eager environment preamble for each wrapper
    $preamble = @"
@echo off
setlocal enableextensions enabledelayedexpansion
set "XDG_CONFIG_HOME=%XDG_CONFIG_HOME%"
set "XDG_CACHE_HOME=%XDG_CACHE_HOME%"
set "XDG_DATA_HOME=%XDG_DATA_HOME%"
set "PIP_CACHE_DIR=%PIP_CACHE_DIR%"
set "RUFF_CACHE_DIR=%RUFF_CACHE_DIR%"
set "BLACK_CACHE_DIR=%BLACK_CACHE_DIR%"
set "MYPY_CACHE_DIR=%MYPY_CACHE_DIR%"
set "UV_CACHE_DIR=%UV_CACHE_DIR%"
set "ESLINT_CACHE=%ESLINT_CACHE%"
set "ESLINT_CACHE_LOCATION=%ESLINT_CACHE_LOCATION%"
"@

    foreach ($src in @($cfg.Sources)) {
      if (-not (Test-Path $src)) { continue }
      $tag = Get-SourceTag -Path $src -Priority $prio
      Get-ChildItem $src -Filter *.cmd | ForEach-Object {
        $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)

        if ($deny -contains $name) { return }
        # keep only first seen by priority
        if ($seen.ContainsKey($name)) { return }
        $seen[$name] = $tag

        $target = $_.FullName
        $wrapper = Join-Path $dest ($name + ".cmd")
        $body = $preamble + "`r`n" + f'"{target}" %*' + "`r`nexit /b %errorlevel%`r`n"
        Set-Content -Path $wrapper -Value $body -Encoding ASCII
      }
    }

    Write-Host ("Built {0} wrappers in {1}" -f $seen.Count, $dest) -ForegroundColor Green
  }
}

Export-ModuleMember -Function Register-Plugin
