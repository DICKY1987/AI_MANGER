<#  
Idempotent installer for the CliStack module.
Usage (one-line remote install):
  Set-ExecutionPolicy -Scope Process Bypass -Force; iwr https://raw.githubusercontent.com/DICKY1987/AI_MANGER/main/AI_MANGER/scripts/Install-CliStack.ps1 -UseBasicParsing | iex

Usage (local install from repo):
  ./scripts/Install-CliStack.ps1
#>
[CmdletBinding()]
param(
  [string]$SourceDir,  # if omitted, resolves relative to this script or downloads from GitHub
  [switch]$RunHealthCheck,
  [string]$GitHubRepo = 'DICKY1987/AI_MANGER',
  [string]$GitHubBranch = 'main'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ModuleFromGitHub {
  param([string]$Repo, [string]$Branch)
  Write-Host "Downloading module from GitHub..."
  $baseUrl = "https://raw.githubusercontent.com/$Repo/$Branch/AI_MANGER/module"
  $tempDir = Join-Path $env:TEMP "CliStack_$(Get-Date -Format 'yyyyMMddHHmmss')"
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
  
  $files = @('CliStack.psd1', 'CliStack.psm1')
  foreach ($file in $files) {
    $url = "$baseUrl/$file"
    $dest = Join-Path $tempDir $file
    try {
      Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
      Write-Verbose "Downloaded $file"
    } catch {
      throw "Failed to download $file from $url`: $_"
    }
  }
  return $tempDir
}

function Resolve-Source {
  param([string]$Dir, [string]$Repo, [string]$Branch, [string]$ScriptPath)
  if ($Dir) { return (Resolve-Path $Dir).Path }
  if ($ScriptPath) {
    $scriptDir = Split-Path -Parent $ScriptPath
    # Check if we're in a local repo (scripts folder exists with module folder nearby)
    $parentDir = Split-Path -Parent $scriptDir
    if (Test-Path (Join-Path $parentDir 'module')) {
      return $parentDir
    }
  }
  # If not local, download from GitHub
  return Get-ModuleFromGitHub -Repo $Repo -Branch $Branch
}

$src = Resolve-Source -Dir $SourceDir -Repo $GitHubRepo -Branch $GitHubBranch -ScriptPath $MyInvocation.MyCommand.Path
$moduleRoot = Join-Path $src 'module'
if (-not (Test-Path $moduleRoot)) {
  # Source is the temp directory with downloaded files
  $moduleRoot = $src
}

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

# Clean up temp directory if we downloaded from GitHub
if ($src -like "$env:TEMP\CliStack_*") {
  Remove-Item -Path $src -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Get-Module -ListAvailable -Name InvokeBuild)) {
  try {
    Write-Host "Installing InvokeBuild..."
    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
      Register-PSRepository -Default -ErrorAction SilentlyContinue
    }
    Install-Module InvokeBuild -Scope CurrentUser -Force -ErrorAction Stop
  } catch {
    Write-Warning "Failed to install InvokeBuild: $($_.Exception.Message)"
    Write-Host "You can install it manually later: Install-Module InvokeBuild -Scope CurrentUser"
  }
}

Import-Module (Join-Path $target 'CliStack.psd1') -Force
Write-Host "✓ CliStack installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Try: Invoke-CliStack -Task Rebuild -Config config/toolstack.config.json -DryRun"

if ($RunHealthCheck) {
  try {
    Write-Host ""
    Write-Host "Running Health.Check (if defined in your build script)..."
    Invoke-CliStack -Task 'Health.Check' -VerboseLog
  } catch {
    Write-Warning "Health.Check not available or failed: $($_.Exception.Message)"
  }
}
