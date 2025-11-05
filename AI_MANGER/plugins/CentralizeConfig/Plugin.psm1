# ModuleName: CentralizeConfig
param()
function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  task CentralizeApply {
    Write-Host "==> Centralizing XDG/config/caches" -ForegroundColor Cyan
    $script = Join-Path $BuildRoot "scripts\centralize_cli_config.ps1"
    if (Test-Path $script) {
      $flag = $Context.BuildWrappers ? "-BuildWrappers" : ""
      try {
        Invoke-WithRetry -MaxAttempts 3 -DelayMs 1000 -ScriptBlock {
          Invoke-Quiet "pwsh -ExecutionPolicy Bypass -File `"$script`" $flag"
        }
      } catch {
        Write-Warning "Failed to centralize config after retries: $_"
      }
    } else {
      Write-Warning "centralize_cli_config.ps1 not found at: $script"
    }
  }
}
Export-ModuleMember -Function Register-Plugin
