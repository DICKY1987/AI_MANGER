# Module: Common Interfaces (placeholder for shared helpers)
# Exported helper: Invoke-Quiet
function Invoke-Quiet {
  param([Parameter(Mandatory)][string]$Command)
  try {
    Write-Host "  $Command" -ForegroundColor DarkGray
    $global:LASTEXITCODE = 0
    cmd /c $Command | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "FAILED ($LASTEXITCODE)" }
  } catch {
    Write-Warning $_
  }
}

# Hardening utilities for cross-volume linking, quarantine, and safety

function Test-IsLink {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path $Path)) { return $false }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
}

function Get-QuarantinePath {
  param(
    [Parameter(Mandatory)][string]$OriginalPath,
    [Parameter(Mandatory)][string]$QuarantineRoot
  )
  $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $name = Split-Path $OriginalPath -Leaf
  $uniqueName = "${name}_${timestamp}_$([Guid]::NewGuid().ToString().Substring(0,8))"
  return Join-Path $QuarantineRoot $uniqueName
}

function Move-ToQuarantine {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$QuarantineRoot
  )
  
  if (-not (Test-Path $Path)) {
    Write-Verbose "Path does not exist, skipping quarantine: $Path"
    return $null
  }
  
  # Ensure quarantine directory exists
  if (-not (Test-Path $QuarantineRoot)) {
    New-Item -ItemType Directory -Force -Path $QuarantineRoot | Out-Null
  }
  
  $destPath = Get-QuarantinePath -OriginalPath $Path -QuarantineRoot $QuarantineRoot
  
  try {
    Move-Item -LiteralPath $Path -Destination $destPath -Force -ErrorAction Stop
    Write-Host "  Quarantined: $Path -> $destPath" -ForegroundColor Yellow
    return $destPath
  } catch {
    Write-Warning "Failed to quarantine $Path : $_"
    return $null
  }
}

function New-DirectoryLink {
  param(
    [Parameter(Mandatory)][string]$LinkPath,
    [Parameter(Mandatory)][string]$TargetPath,
    [string]$QuarantineRoot = "$env:LOCALAPPDATA\CLI_Quarantine"
  )
  
  # Ensure target exists
  if (-not (Test-Path $TargetPath)) {
    New-Item -ItemType Directory -Force -Path $TargetPath | Out-Null
  }
  
  # If link already exists and is correct, nothing to do
  if (Test-IsLink -Path $LinkPath) {
    $existing = Get-Item -LiteralPath $LinkPath -Force
    if ($existing.Target -eq $TargetPath) {
      Write-Verbose "Link already correct: $LinkPath -> $TargetPath"
      return $true
    } else {
      # Link exists but points elsewhere, remove it
      Remove-Item -LiteralPath $LinkPath -Force -Recurse -ErrorAction SilentlyContinue
    }
  }
  
  # If directory exists but is not a link, quarantine it
  if (Test-Path $LinkPath) {
    Move-ToQuarantine -Path $LinkPath -QuarantineRoot $QuarantineRoot | Out-Null
  }
  
  # Ensure parent directory exists
  $parent = Split-Path $LinkPath -Parent
  if (-not (Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  
  # Attempt symlink first (requires Developer Mode on Windows)
  try {
    New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    Write-Host "  Created symlink: $LinkPath -> $TargetPath" -ForegroundColor Green
    return $true
  } catch {
    Write-Verbose "Symlink failed, trying junction: $_"
  }
  
  # Attempt junction (works across volumes on same drive)
  try {
    cmd /c "mklink /J `"$LinkPath`" `"$TargetPath`"" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Write-Host "  Created junction: $LinkPath -> $TargetPath" -ForegroundColor Green
      return $true
    }
  } catch {
    Write-Verbose "Junction failed, falling back to copy: $_"
  }
  
  # Last resort: copy (not ideal, but functional)
  try {
    Copy-Item -LiteralPath $TargetPath -Destination $LinkPath -Recurse -Force -ErrorAction Stop
    Write-Warning "Could not create link, copied instead: $LinkPath (changes won't sync to $TargetPath)"
    return $false
  } catch {
    Write-Warning "All linking methods failed for $LinkPath : $_"
    return $false
  }
}

function Invoke-WithRetry {
  param(
    [Parameter(Mandatory)][scriptblock]$ScriptBlock,
    [int]$MaxAttempts = 3,
    [int]$DelayMs = 500
  )
  
  $attempt = 0
  $lastError = $null
  
  while ($attempt -lt $MaxAttempts) {
    $attempt++
    try {
      return & $ScriptBlock
    } catch {
      $lastError = $_
      if ($attempt -lt $MaxAttempts) {
        Write-Verbose "Attempt $attempt failed, retrying in ${DelayMs}ms: $_"
        Start-Sleep -Milliseconds $DelayMs
      }
    }
  }
  
  throw "Failed after $MaxAttempts attempts: $lastError"
}

function Lock-ResourceFile {
  param(
    [Parameter(Mandatory)][string]$ResourceName,
    [Parameter(Mandatory)][scriptblock]$ScriptBlock,
    [int]$TimeoutSeconds = 30
  )
  
  $tempPath = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
  $lockDir = Join-Path $tempPath "CLI_Locks"
  if (-not (Test-Path -LiteralPath $lockDir -ErrorAction SilentlyContinue)) {
    New-Item -ItemType Directory -Force -Path $lockDir -ErrorAction SilentlyContinue | Out-Null
  }
  
  $lockFile = Join-Path $lockDir "$($ResourceName -replace '[\\/:*?"<>|]', '_').lock"
  $acquired = $false
  $startTime = Get-Date
  
  try {
    # Try to acquire lock
    while (-not $acquired) {
      try {
        # Create lock file exclusively
        $fs = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        if ($fs) {
          $fs.Close()
          $acquired = $true
        }
      } catch {
        if (((Get-Date) - $startTime).TotalSeconds -gt $TimeoutSeconds) {
          throw "Lock timeout after ${TimeoutSeconds}s waiting for: $ResourceName"
        }
        Start-Sleep -Milliseconds 100
      }
    }
    
    # Execute protected code
    return & $ScriptBlock
    
  } finally {
    # Release lock
    if ($acquired -and (Test-Path -LiteralPath $lockFile -ErrorAction SilentlyContinue)) {
      Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
    }
  }
}

Export-ModuleMember -Function Invoke-Quiet, Test-IsLink, Get-QuarantinePath, Move-ToQuarantine, New-DirectoryLink, Invoke-WithRetry, Lock-ResourceFile
