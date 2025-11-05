# Module: Common Interfaces (shared helpers for all plugins)
Set-StrictMode -Version Latest

# Import common modules
$commonDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $commonDir "Logger.psm1") -Force -Global
Import-Module (Join-Path $commonDir "ErrorHandler.psm1") -Force -Global
Import-Module (Join-Path $commonDir "Idempotency.psm1") -Force -Global

# Legacy helper: Invoke-Quiet (preserved for backwards compatibility)
function Invoke-Quiet {
  param(
    [Parameter(Mandatory)]
    [string]$Command,
    [switch]$DryRun
  )
  
  if ($DryRun) {
    Write-LogInfo "[DRY-RUN] Would execute: $Command"
    return
  }
  
  try {
    Write-LogDebug "Executing: $Command"
    $global:LASTEXITCODE = 0
    cmd /c $Command | Out-Host
    if ($LASTEXITCODE -ne 0) { 
      throw "Command failed with exit code $LASTEXITCODE"
    }
    Write-LogDebug "Command completed successfully"
  } catch {
    Write-LogError "Command failed: $Command"
    Write-LogError $_.Exception.Message
    throw
  }
}

# Get DryRun flag from environment or context
function Get-IsDryRun {
  param($Context = $null)
  
  # Check environment variable first
  if ($env:CLISTACK_DRYRUN -eq "true") {
    return $true
  }
  
  # Check context if provided
  if ($Context -and $Context.DryRun) {
    return $true
  }
  
  return $false
}

# Initialize common infrastructure for plugins
function Initialize-PluginContext {
  param(
    [Parameter(Mandatory)]
    [hashtable]$Context
  )
  
  # Initialize logger with config settings
  $logLevel = if ($Context.logging -and $Context.logging.level) { 
    $Context.logging.level 
  } else { 
    "info" 
  }
  
  $logFile = if ($Context.logging -and $Context.logging.logFile) {
    [Environment]::ExpandEnvironmentVariables($Context.logging.logFile)
  } else {
    $null
  }
  
  Initialize-Logger -Level $logLevel -LogFilePath $logFile
  
  Write-LogInfo "Plugin context initialized (LogLevel: $logLevel)"
  if ($logFile) {
    Write-LogDebug "Logging to file: $logFile"
  }
}

Export-ModuleMember -Function Invoke-Quiet, Get-IsDryRun, Initialize-PluginContext
