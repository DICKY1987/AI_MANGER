<# 
ConfigCache_Enforcer.ps1
Purpose:
  Guard against duplicate config/cache folders in project trees by redirecting common
  tool-created directories to centralized locations (via junction/symlink), with optional
  quarantine and real-time watch.

Run examples:
  pwsh -ExecutionPolicy Bypass -File .\ConfigCache_Enforcer.ps1 -Roots "C:\Users\richg\Projects","D:\Work" -Central "C:\Tools\cache" -Quarantine "C:\Tools\quarantine" -Enforce
  pwsh -ExecutionPolicy Bypass -File .\ConfigCache_Enforcer.ps1 -Roots "C:\Users\richg\Projects" -Central "C:\Tools\cache" -Watch -Enforce

Notes:
  - For symlinks without admin rights, enable Windows "Developer Mode" or the script will fall back to NTFS junctions.
  - Directory junctions work across the same volume. If central is on a different volume, we try directory symlinks; if that fails, we copy/move.
  - This script focuses on directory-level caches/configs (not per-file).
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string[]]$Roots,

  [Parameter(Mandatory=$true)]
  [string]$Central,

  [string]$Quarantine = "$env:USERPROFILE\.cache_quarantine",

  [switch]$Watch,

  [switch]$Enforce,

  [switch]$DryRun
)

function Say($s, $c="Cyan") { Write-Host "==> $s" -ForegroundColor $c }
function Ok($s) { Write-Host "✔ $s" -ForegroundColor Green }
function Warn($s) { Write-Host "⚠ $s" -ForegroundColor Yellow }
function Err($s) { Write-Host "✖ $s" -ForegroundColor Red }

# Tool patterns we tend to centralize (directories); edit as needed
$Patterns = @(
  '.ruff_cache',
  '.mypy_cache',
  '.pytest_cache',
  '.eslintcache',
  '.prettier-cache',
  '.cache',                 # common generic cache (careful: scoped below)
  '__pycache__',
  'node_modules\.cache'     # note escaped backslash for regex matching
)

# Compute a stable relative central path for a given project subdir (by hashing project root)
function Get-ProjectKey([string]$ProjectRoot) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($ProjectRoot.ToLowerInvariant())
  $md5 = [System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)
  ($md5 | ForEach-Object { $_.ToString("x2") }) -join ''
}

# Make sure a dir exists
function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    if (-not $DryRun) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    Ok "mkdir $Path"
  }
}

# Is directory a reparse point (symlink/junction)?
function Is-Reparse([string]$Path) {
  try {
    $attr = (Get-Item -LiteralPath $Path -Force).Attributes
    return ($attr -band [IO.FileAttributes]::ReparsePoint) -ne 0
  } catch { return $false }
}

# Try to create link from $From (existing central) to $To (project location)
function Link-Dir([string]$To, [string]$From) {
  if ($DryRun) { Ok "link (dry): $To -> $From"; return $true }
  try {
    # Prefer symlink (works without admin if Developer Mode on)
    cmd /c "mklink /D `"$To`" `"$From`"" | Out-Null
    return $true
  } catch {
    try {
      # Fallback to junction
      cmd /c "mklink /J `"$To`" `"$From`"" | Out-Null
      return $true
    } catch {
      Warn "mklink failed; falling back to copy (may duplicate)"
      try {
        Copy-Item -Recurse -Force -Path $From -Destination $To
        return $true
      } catch {
        Err "Failed to link/copy $To -> $From : $_"
        return $false
      }
    }
  }
}

# Move existing dir to quarantine (safe), then link
function Replace-WithLink([string]$ProjectDir, [string]$CentralDir) {
  Ensure-Dir $CentralDir
  if (Test-Path -LiteralPath $ProjectDir) {
    if (-not (Is-Reparse $ProjectDir)) {
      $q = Join-Path $Quarantine (([IO.Path]::GetFileName($ProjectDir)) + '_' + (Get-Date -Format 'yyyyMMddHHmmssfff'))
      Ensure-Dir (Split-Path $q)
      if ($DryRun) {
        Ok "quarantine (dry): $ProjectDir -> $q"
      } else {
        try { Move-Item -Force -Path $ProjectDir -Destination $q } catch { Warn "Quarantine move failed: $_" }
      }
    } else {
      # Already linked, skip
      return $true
    }
  }
  # Create parent if missing
  $parent = Split-Path $ProjectDir -Parent
  Ensure-Dir $parent
  return (Link-Dir -To $ProjectDir -From $CentralDir)
}

# Decide whether a found directory should be centralized
function Should-Centralize([string]$DirName, [string]$FullPath) {
  # Only centralize if the name matches and it's under a project root
  foreach ($p in $Patterns) {
    if ($DirName -match ("^" + $p + "$")) { return $true }
  }
  return $false
}

# Given a project root and a found dir, compute central target
function Target-For([string]$ProjectRoot, [string]$DirName) {
  $key = Get-ProjectKey $ProjectRoot
  # put each project's caches in a unique bucket under central
  return (Join-Path (Join-Path $Central $key) $DirName)
}

# Enumerate and enforce once
function Enforce-Once() {
  foreach ($root in $Roots) {
    if (-not (Test-Path -LiteralPath $root)) { Warn "Missing root $root"; continue }
    Say "Scanning $root"
    Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
      $name = $_.Name
      # 'node_modules\.cache' is a special regex; check separately
      $match = $false
      foreach ($pat in $Patterns) {
        if ($pat -eq 'node_modules\.cache') {
          if ($_.FullName -match '\\node_modules\\\.cache$') { $match = $true; break }
        } else {
          if ($name -eq $pat) { $match = $true; break }
        }
      }
      if (-not $match) { return }
      if (Is-Reparse $_.FullName) { return } # already linked

      # project root for target key = nearest git root or the watched root
      $proj = (git -C $_.FullName rev-parse --show-toplevel 2>$null)
      if (-not $proj) { $proj = $root }

      $centralTarget = Target-For -ProjectRoot $proj -DirName $name
      if ($Enforce) {
        Replace-WithLink -ProjectDir $_.FullName -CentralDir $centralTarget | Out-Null
      } else {
        Say "Would centralize: $($_.FullName) -> $centralTarget"
      }
    }
  }
}

# Real-time watch (Created/Renamed)
function Start-Watch() {
  foreach ($root in $Roots) {
    $fsw = New-Object IO.FileSystemWatcher
    $fsw.Path = $root
    $fsw.IncludeSubdirectories = $true
    $fsw.NotifyFilter = [IO.NotifyFilters]'DirectoryName'
    $action = {
      param($source, $eventArgs)
      try {
        $full = $eventArgs.FullPath
        if (-not (Test-Path -LiteralPath $full)) { return }
        $item = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue
        if ($null -eq $item -or -not $item.PSIsContainer) { return }
        $name = $item.Name
        # quick match
        $matched = $false
        foreach ($pat in $Patterns) {
          if ($pat -eq 'node_modules\.cache') {
            if ($full -match '\\node_modules\\\.cache$') { $matched = $true; break }
          } else {
            if ($name -eq $pat) { $matched = $true; break }
          }
        }
        if (-not $matched) { return }
        if ((Get-Item -LiteralPath $full -Force).Attributes.ToString().Contains('ReparsePoint')) { return }

        # find project root
        $proj = (git -C $full rev-parse --show-toplevel 2>$null)
        if (-not $proj) { $proj = $root }

        $centralTarget = (Join-Path (Join-Path $using:Central (Get-ProjectKey $proj)) $name)
        if ($using:Enforce) {
          Replace-WithLink -ProjectDir $full -CentralDir $centralTarget | Out-Null
          Write-Host "[enforced] $full -> $centralTarget" -ForegroundColor Green
        } else {
          Write-Host "[detected] $full (would centralize -> $centralTarget)" -ForegroundColor Yellow
        }
      } catch {
        Write-Host "[error] $_" -ForegroundColor Red
      }
    }

    Register-ObjectEvent $fsw Created -Action $action | Out-Null
    Register-ObjectEvent $fsw Renamed -Action $action | Out-Null
    Say "Watching $root"
  }
  Say "Press Ctrl+C to stop. This window must stay open while watching."
  while ($true) { Start-Sleep -Seconds 2 }
}

# Prepare central/quarantine
Ensure-Dir $Central
Ensure-Dir $Quarantine

Enforce-Once

if ($Watch) { Start-Watch } else { Ok "Done (one-time scan). Use -Watch for real-time enforcement." }
