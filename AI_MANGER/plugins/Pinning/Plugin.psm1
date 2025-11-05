# ModuleName: Pinning
param()

function Get-PipxVersion {
  param([Parameter(Mandatory)][string]$Name)
  try {
    # Try to ask pip inside the pipx venv
    $out = cmd /c "pipx runpip $Name show $Name" 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) {
      foreach ($line in $out -split "`r?`n") {
        if ($line -match '^\s*Version:\s*(.+)$') { return $Matches[1].Trim() }
      }
    }
  } catch { }
  return $null
}

function Get-NpmVersion {
  param([Parameter(Mandatory)][string]$Name)
  try {
    $json = cmd /c "npm ls -g $Name --depth=0 --json" 2>$null
    if ($json) {
      $obj = $json | ConvertFrom-Json -ErrorAction Ignore
      if ($obj.dependencies.ContainsKey($Name)) {
        return $obj.dependencies.$Name.version
      }
    }
  } catch { }
  return $null
}

function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  task Pin.Report {
    $pins = $Context.Pins
    if (-not $pins) { Write-Host "No Pins configured." -ForegroundColor Yellow; return }

    Write-Host "==> PIPX versions" -ForegroundColor Cyan
    foreach ($name in $pins.pipx.PSObject.Properties.Name) {
      $want = $pins.pipx.$name
      $have = Get-PipxVersion -Name $name
      "{0,-18} want={1,-12} have={2}" -f $name, $want, ($have ?? "<missing>") | Out-Host
    }

    Write-Host "==> NPM -g versions" -ForegroundColor Cyan
    foreach ($name in $pins.npm.PSObject.Properties.Name) {
      $want = $pins.npm.$name
      $have = Get-NpmVersion -Name $name
      "{0,-28} want={1,-10} have={2}" -f $name, $want, ($have ?? "<missing>") | Out-Host
    }
  }

  task Pin.Sync {
    $pins = $Context.Pins
    if (-not $pins) { Write-Host "No Pins configured." -ForegroundColor Yellow; return }

    Write-Host "==> Enforcing pipx pins" -ForegroundColor Cyan
    foreach ($name in $pins.pipx.PSObject.Properties.Name) {
      $ver = $pins.pipx.$name
      Invoke-Quiet "pipx install ${name}==${ver} --force"
    }

    Write-Host "==> Enforcing npm -g pins" -ForegroundColor Cyan
    foreach ($name in $pins.npm.PSObject.Properties.Name) {
      $ver = $pins.npm.$name
      Invoke-Quiet "npm install -g ${name}@${ver}"
    }
  }
}

Export-ModuleMember -Function Register-Plugin
