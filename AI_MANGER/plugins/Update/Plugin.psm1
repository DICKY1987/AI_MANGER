# ModuleName: Update
param()
function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  function Get-NpmInstalledVersion([string]$Name) {
    try {
      $json = cmd /c "npm ls -g $Name --depth=0 --json" 2>$null
      if ($json) {
        $obj = $json | ConvertFrom-Json -ErrorAction Ignore
        if ($obj -and $obj.dependencies -and $obj.dependencies.ContainsKey($Name)) {
          return $obj.dependencies.$Name.version
        }
      }
    } catch {}
    return $null
  }

  function Get-NpmLatestVersion([string]$Name) {
    try {
      $v = (cmd /c "npm view $Name version" 2>$null)
      if ($LASTEXITCODE -eq 0) { return ($v -split "`r?`n")[0].Trim() }
    } catch {}
    return $null
  }

  function Get-PipxInstalledVersion([string]$Name) {
    try {
      $out = cmd /c "pipx runpip $Name show $Name" 2>$null
      if ($LASTEXITCODE -eq 0 -and $out) {
        foreach ($line in $out -split "`r?`n") {
          if ($line -match '^\s*Version:\s*(.+)$') { return $Matches[1].Trim() }
        }
      }
    } catch {}
    return $null
  }

  function Get-PipxLatestVersion([string]$Name) {
    try {
      # Use pip index to query latest on PyPI (pip >= 23)
      $out = cmd /c "py -m pip index versions $Name" 2>$null
      if ($LASTEXITCODE -eq 0 -and $out) {
        # First line often: "Available versions: 3.0.0, 2.9.1, ..."
        foreach ($line in $out -split "`r?`n") {
          if ($line -match 'Available versions:\s*(.+)$') {
            $list = $Matches[1].Split(',') | ForEach-Object { $_.Trim() }
            if ($list.Count -gt 0) { return $list[0] } # list is usually newest first
          }
        }
      }
    } catch {}
    return $null
  }

  task Update.Check {
    $report = @{
      npm  = @()
      pipx = @()
      time = (Get-Date).ToString("s")
    }

    Write-Host "==> Checking npm package versions..." -ForegroundColor Cyan
    foreach ($name in @($Context.NpmGlobal)) {
      try {
        $have = Get-NpmInstalledVersion $name
        $want = Get-NpmLatestVersion $name
        $report.npm += @{ name=$name; installed=$have; latest=$want; update=(if ($want -and $have -and $want -ne $have) { $true } else { $false }) }
      } catch {
        Write-Warning "Failed to check npm package ${name}: $_"
        $report.npm += @{ name=$name; installed=$null; latest=$null; update=$false; error=$_.ToString() }
      }
    }

    Write-Host "==> Checking pipx package versions..." -ForegroundColor Cyan
    foreach ($name in @($Context.PipxApps)) {
      try {
        $have = Get-PipxInstalledVersion $name
        $want = Get-PipxLatestVersion $name
        $report.pipx += @{ name=$name; installed=$have; latest=$want; update=(if ($want -and $have -and $want -ne $have) { $true } else { $false }) }
      } catch {
        Write-Warning "Failed to check pipx package ${name}: $_"
        $report.pipx += @{ name=$name; installed=$null; latest=$null; update=$false; error=$_.ToString() }
      }
    }

    $dir = [Environment]::ExpandEnvironmentVariables($Context.Reports.Dir)
    if (-not (Test-Path $dir)) { 
      New-Item -ItemType Directory -Force -Path $dir | Out-Null 
    }
    
    $out = Join-Path $dir "updates.json"
    try {
      ($report | ConvertTo-Json -Depth 6) | Set-Content -Path $out -Encoding UTF8 -ErrorAction Stop
      Write-Host "Wrote $out" -ForegroundColor Green
      
      # Summary
      $npmUpdates = ($report.npm | Where-Object { $_.update }).Count
      $pipxUpdates = ($report.pipx | Where-Object { $_.update }).Count
      Write-Host "Found $npmUpdates npm and $pipxUpdates pipx packages with updates available" -ForegroundColor Yellow
    } catch {
      Write-Warning "Failed to write update report: $_"
    }
  }

  task Update.All {
    $failed = @()
    
    Write-Host "==> Updating npm -g packages" -ForegroundColor Cyan
    foreach ($name in @($Context.NpmGlobal)) {
      try {
        Invoke-WithRetry -MaxAttempts 2 -DelayMs 2000 -ScriptBlock {
          cmd /c "npm update -g $name" | Out-Host
          if ($LASTEXITCODE -ne 0) { throw "npm update failed with exit code $LASTEXITCODE" }
        }
      } catch {
        $failed += "npm:$name"
        Write-Warning "Failed to update npm package ${name}: $_"
      }
    }
    
    Write-Host "==> Upgrading pipx apps" -ForegroundColor Cyan
    try {
      Invoke-WithRetry -MaxAttempts 2 -DelayMs 2000 -ScriptBlock {
        cmd /c "pipx upgrade --all --include-injected" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "pipx upgrade failed with exit code $LASTEXITCODE" }
      }
    } catch {
      $failed += "pipx:all"
      Write-Warning "Failed to upgrade pipx packages: $_"
    }
    
    if ($failed.Count -gt 0) {
      Write-Warning "Failed to update $($failed.Count) package(s): $($failed -join ', ')"
    } else {
      Write-Host "All packages updated successfully" -ForegroundColor Green
    }
  }
}
Export-ModuleMember -Function Register-Plugin
