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
      try {
        Lock-ResourceFile -ResourceName "MasterBin.Clean" -ScriptBlock {
          Get-ChildItem $dest -Filter *.cmd -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
          Write-Host "Cleaned $dest" -ForegroundColor Green
        }
      } catch {
        Write-Warning "Failed to clean MasterBin: $_"
      }
    }
  }

  task MasterBin.Rebuild -Depends MasterBin.Clean {
    $cfg   = $Context.MasterBin
    if (-not $cfg.Enable) {
      Write-Host "MasterBin.Enable is false; skipping (enable in config to use)." -ForegroundColor Yellow
      return
    }

    try {
      Lock-ResourceFile -ResourceName "MasterBin.Rebuild" -TimeoutSeconds 60 -ScriptBlock {
        $dest  = $cfg.Path
        if (-not (Test-Path $dest)) { 
          New-Item -ItemType Directory -Force -Path $dest | Out-Null 
        }

        $deny  = @($cfg.DenyList)
        $prio  = @($cfg.Priority)
        $seen  = @{}
        $collisions = @()

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
          if (-not (Test-Path $src)) { 
            Write-Verbose "Source path not found, skipping: $src"
            continue 
          }
          
          $tag = Get-SourceTag -Path $src -Priority $prio
          
          try {
            Get-ChildItem $src -Filter *.cmd -ErrorAction Stop | ForEach-Object {
              $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)

              if ($deny -contains $name) { 
                Write-Verbose "Skipping denied: $name"
                return 
              }
              
              # Collision detection: keep only first seen by priority
              if ($seen.ContainsKey($name)) { 
                $collisions += @{
                  name = $name
                  kept = $seen[$name]
                  skipped = $tag
                  keptPath = $null
                  skippedPath = $_.FullName
                }
                Write-Verbose "Collision: $name already wrapped by $($seen[$name]), skipping $tag"
                return 
              }
              
              $seen[$name] = $tag

              $target = $_.FullName
              $wrapper = Join-Path $dest ($name + ".cmd")
              
              # Validate target exists before creating wrapper
              if (-not (Test-Path $target)) {
                Write-Warning "Target does not exist, skipping wrapper: $target"
                return
              }
              
              try {
                $body = $preamble + "`r`n" + "`"$target`" %*" + "`r`nexit /b %errorlevel%`r`n"
                Set-Content -Path $wrapper -Value $body -Encoding ASCII -ErrorAction Stop
              } catch {
                Write-Warning "Failed to create wrapper $wrapper : $_"
              }
            }
          } catch {
            Write-Warning "Failed to process source $src : $_"
          }
        }

        Write-Host ("Built {0} wrappers in {1}" -f $seen.Count, $dest) -ForegroundColor Green
        
        if ($collisions.Count -gt 0) {
          Write-Host ("Resolved {0} collisions by priority:" -f $collisions.Count) -ForegroundColor Yellow
          foreach ($c in $collisions) {
            Write-Host ("  {0}: kept {1}, skipped {2}" -f $c.name, $c.kept, $c.skipped) -ForegroundColor DarkYellow
          }
        }
      }
    } catch {
      Write-Warning "MasterBin.Rebuild failed: $_"
      throw
    }
  }
}

Export-ModuleMember -Function Register-Plugin
