#requires -Version 7.0
param(
  [string]$ConfigPath = ".\config\toolstack.config.json"
)

# Import InvokeBuild (requires: Install-Module InvokeBuild -Scope CurrentUser)
Import-Module InvokeBuild -ErrorAction Stop

# Load config
if (-not (Test-Path $ConfigPath)) {
  throw "Config not found: $ConfigPath"
}
$Global:ToolStackConfig = Get-Content $ConfigPath | ConvertFrom-Json

# Utility: Write status
function Say($msg, $color="Cyan") { Write-Host "==> $msg" -ForegroundColor $color }
function Ok($msg) { Write-Host "✔ $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "⚠ $msg" -ForegroundColor Yellow }

# Discover and import plugins
$pluginRoots = Get-ChildItem -Path "$PSScriptRoot\plugins" -Directory -ErrorAction SilentlyContinue
foreach ($pr in $pluginRoots) {
  $plugin = Join-Path $pr.FullName "Plugin.psm1"
  if (Test-Path $plugin) {
    Import-Module $plugin -Force
    if (Get-Command -Name Register-Plugin -Module (Split-Path $plugin -LeafBase) -ErrorAction SilentlyContinue) {
      & (Get-Command -Name Register-Plugin -Module (Split-Path $plugin -LeafBase)) -Context $Global:ToolStackConfig -BuildRoot $PSScriptRoot
      Ok "Plugin loaded: $($pr.Name)"
    } else {
      Warn "No Register-Plugin in $($pr.Name); skipping"
    }
  }
}

# Aggregate tasks (across plugins)
task Bootstrap -Depends PipxInstall, NpmInstall, CentralizeApply
task Rebuild   -Depends Bootstrap, WatcherEnforce, AuditSetup
task Verify {
  Say "Verifying core tools (non-fatal)"
  cmd /c "git --version"        | Out-Host
  cmd /c "node --version"       | Out-Host
  cmd /c "py -3.12 --version"   | Out-Host
  cmd /c "gh --version"         | Out-Host
  cmd /c "pwsh --version"       | Out-Host
  cmd /c "pipx --version"       | Out-Host
  cmd /c "pnpm --version"       | Out-Host
  cmd /c "aider --version"      | Out-Host
  cmd /c "ruff --version"       | Out-Host
  cmd /c "black --version"      | Out-Host
  cmd /c "langgraph --version"  | Out-Host
  cmd /c "gemini --version"     | Out-Host
  cmd /c "claude-code --version"| Out-Host
  cmd /c "copilot --version"    | Out-Host
}

# Default
task . Rebuild
