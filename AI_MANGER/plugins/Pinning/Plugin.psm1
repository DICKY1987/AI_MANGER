# ModuleName: Pinning
param()

function Get-PipxVersion {
  param([Parameter(Mandatory)][string]$Name)
  try {
    # Try to ask pip inside the pipx venv
    $out = cmd /c "pipx runpip $Name show $Name" 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) {
      foreach ($line in $out -split "`r?`n") {
        if ($line -match '^\s*Version:\s*(.+)$') { return $Matches[1].Trim() }
      }
    }
  } catch { 
    Write-Verbose "Failed to get pipx version for ${Name}: $_"
  }
  return $null
}

function Get-NpmVersion {
  param([Parameter(Mandatory)][string]$Name)
  try {
    $json = cmd /c "npm ls -g $Name --depth=0 --json" 2>$null
    if ($json) {
      $obj = $json | ConvertFrom-Json -ErrorAction Ignore
      if ($obj.dependencies.ContainsKey($Name)) {
        return $obj.dependencies.$Name.version
      }
    }
  } catch { 
    Write-Verbose "Failed to get npm version for ${Name}: $_"
  }
  return $null
}

function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  task Pin.Report {
    $pins = $Context.Pins
    if (-not $pins) { Write-Host "No Pins configured." -ForegroundColor Yellow; return }

    $report = @{
      time = (Get-Date).ToString("s")
      pipx = @()
      npm = @()
    }

    Write-Host "==> PIPX versions" -ForegroundColor Cyan
    foreach ($name in $pins.pipx.PSObject.Properties.Name) {
      $want = $pins.pipx.$name
      $have = Get-PipxVersion -Name $name
      $status = if ($have -eq $want) { "OK" } elseif ($null -eq $have) { "MISSING" } else { "DRIFT" }
      "{0,-18} want={1,-12} have={2,-12} [{3}]" -f $name, $want, ($have ?? "<missing>"), $status | Out-Host
      $report.pipx += @{ name=$name; want=$want; have=$have; status=$status }
    }

    Write-Host "==> NPM -g versions" -ForegroundColor Cyan
    foreach ($name in $pins.npm.PSObject.Properties.Name) {
      $want = $pins.npm.$name
      $have = Get-NpmVersion -Name $name
      $status = if ($have -eq $want) { "OK" } elseif ($null -eq $have) { "MISSING" } else { "DRIFT" }
      "{0,-28} want={1,-10} have={2,-12} [{3}]" -f $name, $want, ($have ?? "<missing>"), $status | Out-Host
      $report.npm += @{ name=$name; want=$want; have=$have; status=$status }
    }

    # Write report
    $reportDir = [Environment]::ExpandEnvironmentVariables($Context.Reports.Dir)
    if (-not (Test-Path $reportDir)) { 
      New-Item -ItemType Directory -Force -Path $reportDir | Out-Null 
    }
    $outPath = Join-Path $reportDir "pins.json"
    try {
      ($report | ConvertTo-Json -Depth 6) | Set-Content -Path $outPath -Encoding UTF8 -ErrorAction Stop
      Write-Host "Wrote pin report: $outPath" -ForegroundColor Green
    } catch {
      Write-Warning "Failed to write pin report: $_"
    }
  }

  task Pin.Sync {
    $pins = $Context.Pins
    if (-not $pins) { Write-Host "No Pins configured." -ForegroundColor Yellow; return }

    $failed = @()

    Write-Host "==> Enforcing pipx pins" -ForegroundColor Cyan
    foreach ($name in $pins.pipx.PSObject.Properties.Name) {
      $ver = $pins.pipx.$name
      try {
        Invoke-WithRetry -MaxAttempts 2 -DelayMs 2000 -ScriptBlock {
          Invoke-Quiet "pipx install ${name}==${ver} --force"
        }
      } catch {
        $failed += "pipx:${name}@${ver}"
        Write-Warning "Failed to pin pipx package ${name}@${ver} after retries: $_"
      }
    }

    Write-Host "==> Enforcing npm -g pins" -ForegroundColor Cyan
    foreach ($name in $pins.npm.PSObject.Properties.Name) {
      $ver = $pins.npm.$name
      try {
        Invoke-WithRetry -MaxAttempts 2 -DelayMs 2000 -ScriptBlock {
          Invoke-Quiet "npm install -g ${name}@${ver}"
        }
      } catch {
        $failed += "npm:${name}@${ver}"
        Write-Warning "Failed to pin npm package ${name}@${ver} after retries: $_"
      }
    }

    if ($failed.Count -gt 0) {
      Write-Warning "Failed to sync $($failed.Count) package(s): $($failed -join ', ')"
    } else {
      Write-Host "All pins synchronized successfully" -ForegroundColor Green
    }
  }
}

Export-ModuleMember -Function Register-Plugin
