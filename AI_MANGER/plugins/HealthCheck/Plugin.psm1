# ModuleName: HealthCheck
param()

function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force
  
  # Initialize plugin context
  Initialize-PluginContext -Context $Context

  function Expand-Env([string]$s) { [Environment]::ExpandEnvironmentVariables($s) }
  
  function Check-Cmd([string]$name) {
    $path = (Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    return @{ cmd=$name; path=$path; ok=([bool]$path) }
  }
  
  function Check-Dir([string]$path) {
    $p = Expand-Env $path
    return @{ path=$p; exists=(Test-Path $p) }
  }
  
  function Path-OrderOk([string[]]$wantOrder) {
    $u = [Environment]::GetEnvironmentVariable('Path','User')
    $parts = ($u -split ';') | Where-Object { $_ } 
    $idx = @()
    foreach ($w in $wantOrder) {
      $i = $parts.IndexOf($w)
      $idx += $i
    }
    # All must exist and be in ascending order (front-loaded)
    $exists = -not ($idx -contains -1)
    $ordered = $exists -and (@($idx) -join ',' -match '^\d+(,\d+)*$') -and ($idx -eq ($idx | Sort-Object))
    return @{ exists=$exists; ordered=$ordered; indices=$idx; userPath=$u }
  }

  task Health.Check {
    Write-LogInfo "Running health checks..."
    
    $isDryRun = Get-IsDryRun -Context $Context
    $reportDir = Expand-Env $Context.Reports.Dir
    
    if (-not $isDryRun) {
      if (-not (Test-Path $reportDir)) { 
        New-Item -ItemType Directory -Force -Path $reportDir | Out-Null 
        Write-LogDebug "Created report directory: $reportDir"
      }
    }
    
    $out = Join-Path $reportDir "health.json"

    $wantOrder = @(
      "C:\Tools\pipx\bin",
      "C:\Tools\pnpm\bin",
      "C:\Tools\node\npm",
      "C:\Tools\go\bin",
      "C:\Tools\cargo\bin"
    )

    Write-LogDebug "Gathering environment information"
    $res = @{
      time = (Get-Date).ToString("s")
      env  = @{
        PIPX_HOME            = $env:PIPX_HOME
        PIPX_BIN_DIR         = $env:PIPX_BIN_DIR
        PNPM_HOME            = $env:PNPM_HOME
        NPM_PREFIX           = (cmd /c "npm config get prefix")
        XDG_CONFIG_HOME      = $env:XDG_CONFIG_HOME
        XDG_CACHE_HOME       = $env:XDG_CACHE_HOME
        XDG_DATA_HOME        = $env:XDG_DATA_HOME
        PIP_CACHE_DIR        = $env:PIP_CACHE_DIR
        ESLINT_CACHE         = $env:ESLINT_CACHE
        ESLINT_CACHE_LOCATION= $env:ESLINT_CACHE_LOCATION
      }
      dirs = @(
        Check-Dir "C:\Tools\pipx\bin",
        Check-Dir "C:\Tools\node\npm",
        Check-Dir "C:\Tools\pnpm\bin",
        Check-Dir "C:\Tools\cache",
        Check-Dir "C:\Tools\config",
        Check-Dir "C:\Tools\data"
      )
      pathOrder = (Path-OrderOk $wantOrder)
      commands = @(
        Check-Cmd "git",
        Check-Cmd "node",
        Check-Cmd "py",
        Check-Cmd "pipx",
        Check-Cmd "pnpm",
        Check-Cmd "aider",
        Check-Cmd "ruff",
        Check-Cmd "black",
        Check-Cmd "langgraph",
        Check-Cmd "gemini",
        Check-Cmd "claude-code",
        Check-Cmd "copilot"
      )
      advice = @()
    }

    Write-LogDebug "Analyzing health check results"
    if (-not $res.pathOrder.exists -or -not $res.pathOrder.ordered) {
      $advice = "Reorder User PATH to front-load: " + ($wantOrder -join ';')
      $res.advice += $advice
      Write-LogWarning $advice
    }
    
    foreach ($d in $res.dirs) {
      if (-not $d.exists) { 
        $advice = "Create missing directory: " + $d.path
        $res.advice += $advice
        Write-LogWarning $advice
      }
    }
    
    foreach ($c in $res.commands) {
      if (-not $c.ok) { 
        $advice = "Install or expose on PATH: " + $c.cmd
        $res.advice += $advice
        Write-LogWarning $advice
      }
    }

    if (-not $isDryRun) {
      ($res | ConvertTo-Json -Depth 6) | Set-Content -Path $out -Encoding UTF8
      Write-LogSuccess "Health check report written to: $out"
    } else {
      Write-LogInfo "[DRY-RUN] Would write health check report to: $out"
      Write-LogInfo "Found $($res.advice.Count) potential issues"
    }
  }
}

Export-ModuleMember -Function Register-Plugin
