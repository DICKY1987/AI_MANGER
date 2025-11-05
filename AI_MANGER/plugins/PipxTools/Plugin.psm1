# ModuleName: PipxTools
param()
function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  task PipxInstall {
    Write-Host "==> Installing Python CLIs via pipx" -ForegroundColor Cyan
    cmd /c "py -3 -m pip install --user --upgrade pip pipx" | Out-Host
    cmd /c "pipx ensurepath" | Out-Host
    $apps = @($Context.PipxApps)
    foreach ($a in $apps) {
      Invoke-Quiet "pipx install $a --force"
    }
  }
}
Export-ModuleMember -Function Register-Plugin
