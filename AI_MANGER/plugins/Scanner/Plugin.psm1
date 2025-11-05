# ModuleName: Scanner
param()
function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  function Expand-Env([string]$s) { [Environment]::ExpandEnvironmentVariables($s) }

  function Get-ProjectRoot([string]$path, [string]$fallback) {
    try {
      $root = (git -C $path rev-parse --show-toplevel 2>$null)
      if ($root) { return $root }
    } catch {}
    return $fallback
  }

  function Match-CachePattern([string]$full, [string]$name, [string[]]$patterns) {
    foreach ($p in $patterns) {
      if ($p -eq 'node_modules\.cache') {
        if ($full -match '\\node_modules\\\.cache$') { return $true }
      } else {
        if ($name -eq $p) { return $true }
      }
    }
    return $false
  }

  task Scan.Duplicates {
    $roots = @($Context.Scan.Roots)
    $minKB = [int]$Context.Scan.MinSizeKBForHash
    $hashMap = @{}
    $groups = @()
    $errors = @()

    Write-Host "==> Scanning for duplicate files..." -ForegroundColor Cyan
    foreach ($root in $roots) {
      if (-not (Test-Path $root)) { 
        Write-Warning "Scan root not found, skipping: $root"
        continue 
      }
      
      try {
        Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.Length -ge ($minKB * 1024) } |
          ForEach-Object {
            try {
              $h = Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName -ErrorAction Stop
              $key = $h.Hash
              if (-not $hashMap.ContainsKey($key)) { $hashMap[$key] = @() }
              $hashMap[$key] += $_.FullName
            } catch {
              $errors += @{ path=$_.FullName; error=$_.ToString() }
              Write-Verbose "Failed to hash file: $($_.FullName) - $_"
            }
          }
      } catch {
        Write-Warning "Failed to scan root ${root}: $_"
        $errors += @{ path=$root; error=$_.ToString() }
      }
    }

    foreach ($k in $hashMap.Keys) {
      $arr = $hashMap[$k]
      if ($arr.Count -gt 1) {
        $groups += @{ hash=$k; count=$arr.Count; files=$arr }
      }
    }

    $report = @{ 
      time=(Get-Date).ToString("s")
      duplicates=$groups
      totalDuplicateGroups=$groups.Count
      errors=$errors
    }
    
    $dir = Expand-Env $Context.Reports.Dir
    if (-not (Test-Path $dir)) { 
      New-Item -ItemType Directory -Force -Path $dir | Out-Null 
    }
    
    $out = Join-Path $dir "duplicates.json"
    try {
      ($report | ConvertTo-Json -Depth 6) | Set-Content -Path $out -Encoding UTF8 -ErrorAction Stop
      Write-Host "Wrote $out" -ForegroundColor Green
      Write-Host "Found $($groups.Count) duplicate file groups" -ForegroundColor Yellow
    } catch {
      Write-Warning "Failed to write duplicates report: $_"
    }
  }

  task Scan.Misplaced {
    $roots      = @($Context.Scan.Roots)
    $allowed    = @($Context.Scan.AllowCentral)
    $patterns   = @($Context.Scan.Patterns)
    $findings   = @()
    $errors     = @()

    Write-Host "==> Scanning for misplaced cache/config directories..." -ForegroundColor Cyan
    foreach ($root in $roots) {
      if (-not (Test-Path $root)) { 
        Write-Warning "Scan root not found, skipping: $root"
        continue 
      }
      
      try {
        Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
          try {
            $full = $_.FullName
            $name = $_.Name
            $ok = $false
            foreach ($a in $allowed) {
              if ($full.StartsWith($a, [System.StringComparison]::OrdinalIgnoreCase)) { $ok = $true; break }
            }
            if ($ok) { return }

            if (Match-CachePattern -full $full -name $name -patterns $patterns) {
              $proj = Get-ProjectRoot -path $full -fallback $root
              $findings += @{ path=$full; name=$name; project=$proj }
            }
          } catch {
            $errors += @{ path=$_.FullName; error=$_.ToString() }
            Write-Verbose "Error processing directory $($_.FullName): $_"
          }
        }
      } catch {
        Write-Warning "Failed to scan root ${root}: $_"
        $errors += @{ path=$root; error=$_.ToString() }
      }
    }

    $report = @{ 
      time=(Get-Date).ToString("s")
      misplaced=$findings
      totalMisplaced=$findings.Count
      errors=$errors
    }
    
    $dir = [Environment]::ExpandEnvironmentVariables($Context.Reports.Dir)
    if (-not (Test-Path $dir)) { 
      New-Item -ItemType Directory -Force -Path $dir | Out-Null 
    }
    
    $out = Join-Path $dir "misplaced.json"
    try {
      ($report | ConvertTo-Json -Depth 6) | Set-Content -Path $out -Encoding UTF8 -ErrorAction Stop
      Write-Host "Wrote $out" -ForegroundColor Green
      Write-Host "Found $($findings.Count) misplaced cache/config directories" -ForegroundColor Yellow
    } catch {
      Write-Warning "Failed to write misplaced report: $_"
    }
  }

  task Scan.Report -Depends Scan.Misplaced, Scan.Duplicates { }
}
Export-ModuleMember -Function Register-Plugin
