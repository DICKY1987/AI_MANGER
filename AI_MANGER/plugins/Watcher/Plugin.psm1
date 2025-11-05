# ModuleName: Watcher
param()
function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  task WatcherEnforce {
    Write-Host "==> Enforcing cache centralization once" -ForegroundColor Cyan
    $script = Join-Path $BuildRoot "scripts\ConfigCache_Enforcer.ps1"
    if (Test-Path $script) {
      $roots = ($Context.WatchRoots | ForEach-Object { '"{0}"' -f $_ }) -join ','
      $central = $Context.CentralCache
      Invoke-Quiet ('pwsh -ExecutionPolicy Bypass -File "{0}" -Roots {1} -Central "{2}" -Enforce' -f $script, $roots, $central)
    } else {
      Write-Warning "ConfigCache_Enforcer.ps1 not found"
    }
  }

  task WatcherWatch {
    Write-Host "==> Starting real-time watcher (Press Ctrl+C to stop)" -ForegroundColor Cyan
    $script = Join-Path $BuildRoot "scripts\ConfigCache_Enforcer.ps1"
    if (Test-Path $script) {
      $roots = ($Context.WatchRoots | ForEach-Object { '"{0}"' -f $_ }) -join ','
      $central = $Context.CentralCache
      Invoke-Quiet ('pwsh -ExecutionPolicy Bypass -File "{0}" -Roots {1} -Central "{2}" -Watch -Enforce' -f $script, $roots, $central)
    } else {
      Write-Warning "ConfigCache_Enforcer.ps1 not found"
    }
  }
}
Export-ModuleMember -Function Register-Plugin
