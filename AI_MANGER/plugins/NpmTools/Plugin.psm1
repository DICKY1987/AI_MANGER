# ModuleName: NpmTools
param()
function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  task NpmInstall {
    Write-Host "==> Installing Node CLIs globally" -ForegroundColor Cyan
    $prefix = "$($Context.ToolsRoot)\node"
    Invoke-Quiet "npm config set prefix `"$prefix`" --global"
    Invoke-Quiet "npm install -g pnpm"
    Invoke-Quiet "pnpm config set store-dir `"$($Context.ToolsRoot)\pnpm\store`""
    foreach ($pkg in @($Context.NpmGlobal)) {
      Invoke-Quiet "npm install -g $pkg"
    }
    # Copilot with fallback
    $ok = $false
    foreach ($c in @($Context.CopilotPkgs)) {
      try {
        Invoke-Quiet "npm install -g $c"
        $ok = $true
        break
      } catch { }
    }
    if (-not $ok) { Write-Warning "Copilot CLI failed to install via npm. Install manually if needed." }
  }
}
Export-ModuleMember -Function Register-Plugin
