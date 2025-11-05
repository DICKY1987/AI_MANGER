# ModuleName: NpmTools
param()

function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force
  
  # Initialize plugin context
  Initialize-PluginContext -Context $Context
  
  task NpmInstall {
    Write-LogInfo "==> Installing Node CLIs globally"
    
    $isDryRun = Get-IsDryRun -Context $Context
    $prefix = "$($Context.ToolsRoot)\node"
    
    # Check if we should skip (idempotency)
    $inputs = @{
      packages = ($Context.NpmGlobal -join ",")
      prefix = $prefix
    }
    
    if (Test-ShouldSkipTask -TaskName "NpmInstall" -CurrentInputs $inputs -MaxAgeMinutes 60) {
      Write-LogSuccess "NpmInstall already completed recently with same configuration"
      return
    }
    
    # Check prerequisites
    if (-not (Test-Prerequisite -Name "npm" -Type Command)) {
      Write-LogError "npm is not available. Please install Node.js first."
      throw "Missing prerequisite: npm"
    }
    
    # Configure npm prefix
    Write-LogInfo "Configuring npm prefix: $prefix"
    
    # Validate prefix path to prevent injection
    if ($prefix -notmatch '^[a-zA-Z0-9\\/:\-_\. ]+$') {
      Write-LogError "Invalid prefix path format: $prefix"
      throw "Invalid configuration: ToolsRoot contains invalid characters"
    }
    
    Invoke-SafeCommand -Command "npm config set prefix `"$prefix`" --global" -DryRun:$isDryRun -ErrorMessage "Failed to set npm prefix"
    
    # Install pnpm
    Write-LogInfo "Installing pnpm"
    Invoke-SafeCommand -Command "npm install -g pnpm" -DryRun:$isDryRun -ErrorMessage "Failed to install pnpm" -ContinueOnError
    
    # Configure pnpm store
    $pnpmStore = "$($Context.ToolsRoot)\pnpm\store"
    Write-LogDebug "Configuring pnpm store: $pnpmStore"
    Invoke-SafeCommand -Command "pnpm config set store-dir `"$pnpmStore`"" -DryRun:$isDryRun -ErrorMessage "Failed to configure pnpm" -ContinueOnError
    
    # Install packages
    foreach ($pkg in @($Context.NpmGlobal)) {
      Write-LogInfo "Installing npm package: $pkg"
      
      # Validate package name to prevent injection
      if ($pkg -notmatch '^[@a-zA-Z0-9/\-_.]+$') {
        Write-LogWarning "Invalid package name format, skipping: $pkg"
        continue
      }
      
      # Check if already installed (idempotency)
      if (Test-PackageInstalled -PackageName $pkg -Manager "npm") {
        Write-LogDebug "Package $pkg is already installed"
        continue
      }
      
      $result = Invoke-SafeCommand -Command "npm install -g $pkg" -DryRun:$isDryRun -ErrorMessage "Failed to install $pkg" -ContinueOnError
      if ($result.Success) {
        Write-LogSuccess "Installed $pkg"
      }
    }
    
    # Install Copilot with fallback
    Write-LogInfo "Installing GitHub Copilot CLI"
    $copilotInstalled = $false
    foreach ($c in @($Context.CopilotPkgs)) {
      Write-LogDebug "Trying Copilot package: $c"
      $result = Invoke-SafeCommand -Command "npm install -g $c" -DryRun:$isDryRun -ErrorMessage "Failed to install $c" -ContinueOnError
      if ($result.Success) {
        Write-LogSuccess "Installed Copilot: $c"
        $copilotInstalled = $true
        break
      }
    }
    
    if (-not $copilotInstalled -and -not $isDryRun) {
      Write-LogWarning "Copilot CLI failed to install via npm. Install manually if needed."
    }
    
    # Save completion state
    if (-not $isDryRun) {
      Save-TaskCompletion -TaskName "NpmInstall" -Inputs $inputs
      Write-LogSuccess "NpmInstall completed successfully"
    }
  }
}

Export-ModuleMember -Function Register-Plugin
