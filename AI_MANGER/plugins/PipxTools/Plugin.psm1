# ModuleName: PipxTools
param()

function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force
  
  # Initialize plugin context
  Initialize-PluginContext -Context $Context
  
  task PipxInstall {
    Write-LogInfo "==> Installing Python CLIs via pipx"
    
    $isDryRun = Get-IsDryRun -Context $Context
    
    # Check if we should skip (idempotency)
    $inputs = @{
      packages = ($Context.PipxApps -join ",")
    }
    
    if (Test-ShouldSkipTask -TaskName "PipxInstall" -CurrentInputs $inputs -MaxAgeMinutes 60) {
      Write-LogSuccess "PipxInstall already completed recently with same configuration"
      return
    }
    
    # Check prerequisites
    if (-not (Test-Prerequisite -Name "py" -Type Command)) {
      Write-LogError "Python (py launcher) is not available. Please install Python first."
      throw "Missing prerequisite: py"
    }
    
    # Upgrade pip and pipx
    Write-LogInfo "Upgrading pip and pipx"
    if (-not $isDryRun) {
      cmd /c "py -3 -m pip install --user --upgrade pip pipx" | Out-Host
      if ($LASTEXITCODE -ne 0) {
        Write-LogWarning "Failed to upgrade pip/pipx (exit code: $LASTEXITCODE)"
      }
    } else {
      Write-LogInfo "[DRY-RUN] Would execute: py -3 -m pip install --user --upgrade pip pipx"
    }
    
    # Ensure pipx path is configured
    Write-LogInfo "Ensuring pipx path configuration"
    if (-not $isDryRun) {
      cmd /c "pipx ensurepath" | Out-Host
    } else {
      Write-LogInfo "[DRY-RUN] Would execute: pipx ensurepath"
    }
    
    # Install packages
    $apps = @($Context.PipxApps)
    foreach ($a in $apps) {
      Write-LogInfo "Installing pipx package: $a"
      
      # Validate package name to prevent injection
      if ($a -notmatch '^[@a-zA-Z0-9/\-_.]+$') {
        Write-LogWarning "Invalid package name format, skipping: $a"
        continue
      }
      
      # Check if already installed (idempotency)
      if (Test-PackageInstalled -PackageName $a -Manager "pipx") {
        Write-LogDebug "Package $a is already installed"
        continue
      }
      
      $result = Invoke-SafeCommand -Command "pipx install $a --force" -DryRun:$isDryRun -ErrorMessage "Failed to install $a" -ContinueOnError
      if ($result.Success) {
        Write-LogSuccess "Installed $a"
      }
    }
    
    # Save completion state
    if (-not $isDryRun) {
      Save-TaskCompletion -TaskName "PipxInstall" -Inputs $inputs
      Write-LogSuccess "PipxInstall completed successfully"
    }
  }
}

Export-ModuleMember -Function Register-Plugin
