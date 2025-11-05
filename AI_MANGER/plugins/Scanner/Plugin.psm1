# ModuleName: Scanner
param()
function Register-Plugin {
  param($Context, $BuildRoot)

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

    foreach ($root in $roots) {
      if (-not (Test-Path $root)) { continue }
      Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge ($minKB * 1024) } |
        ForEach-Object {
          try {
            $h = Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName
            $key = $h.Hash
            if (-not $hashMap.ContainsKey($key)) { $hashMap[$key] = @() }
            $hashMap[$key] += $_.FullName
          } catch {}
        }
    }

    foreach ($k in $hashMap.Keys) {
      $arr = $hashMap[$k]
      if ($arr.Count -gt 1) {
        $groups += @{ hash=$k; count=$arr.Count; files=$arr }
      }
    }

    $report = @{ time=(Get-Date).ToString("s"); duplicates=$groups }
    $dir = Expand-Env $Context.Reports.Dir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $out = Join-Path $dir "duplicates.json"
    ($report | ConvertTo-Json -Depth 6) | Set-Content -Path $out -Encoding UTF8
    Write-Host "Wrote $out" -ForegroundColor Green
  }

  task Scan.Misplaced {
    $roots      = @($Context.Scan.Roots)
    $allowed    = @($Context.Scan.AllowCentral)
    $patterns   = @($Context.Scan.Patterns)
    $findings   = @()

    foreach ($root in $roots) {
      if (-not (Test-Path $root)) { continue }
      Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
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
      }
    }

    $report = @{ time=(Get-Date).ToString("s"); misplaced=$findings }
    $dir = [Environment]::ExpandEnvironmentVariables($Context.Reports.Dir)
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $out = Join-Path $dir "misplaced.json"
    ($report | ConvertTo-Json -Depth 6) | Set-Content -Path $out -Encoding UTF8
    Write-Host "Wrote $out" -ForegroundColor Green
  }

  task Scan.Report -Depends Scan.Misplaced, Scan.Duplicates { }
}
Export-ModuleMember -Function Register-Plugin
