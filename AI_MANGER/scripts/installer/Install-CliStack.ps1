<#  
Idempotent installer for the CliStack module.
Usage (one-line):
  Set-ExecutionPolicy -Scope Process Bypass -Force; iwr https://raw.githubusercontent.com/DICKY1987/AI_MANGER/main/scripts/installer/Install-CliStack.ps1 -UseBasicParsing | iex
#>
[CmdletBinding()]
param(
  [string]$SourceDir,  # if omitted, resolves relative to this script
  [switch]$RunHealthCheck
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Resolve-Source {
  param([string]$Dir)
  if ($Dir) { return (Resolve-Path $Dir).Path }
  if ($MyInvocation.MyCommand.Path) {
    return (Split-Path -Parent $MyInvocation.MyCommand.Path)
  }
  return (Get-Location).Path
}
$src = Resolve-Source -Dir $SourceDir
$moduleRoot = Join-Path $src 'module'
$target = Join-Path $HOME 'Documents\PowerShell\Modules\CliStack'
$targetParent = Split-Path -Parent $target
New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
if (Test-Path $target) {
  Write-Host "Updating existing CliStack at $target"
} else {
  Write-Host "Installing CliStack to $target"
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -Recurse -Force -Path (Join-Path $moduleRoot '*') -Destination $target
if (-not (Get-Module -ListAvailable -Name InvokeBuild)) {
  try { Install-Module InvokeBuild -Scope CurrentUser -Force -ErrorAction Stop }
  catch { throw "Failed to install InvokeBuild: $($_.Exception.Message)" }
}
Import-Module CliStack -Force
Write-Host "CliStack installed. Try: Invoke-CliStack -Task Rebuild -Config config/toolstack.config.json -DryRun"
if ($RunHealthCheck) {
  try {
    Write-Host "Running Health.Check (if defined in your build script)..."
    Invoke-CliStack -Task 'Health.Check' -VerboseLog
  } catch {
    Write-Warning "Health.Check not available or failed: $($_.Exception.Message)"
  }
}
