Set-StrictMode -Version Latest

function Test-ModuleAvailable {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Module -ListAvailable -Name $Name)
}

function Ensure-InvokeBuild {
    if (-not (Test-ModuleAvailable -Name 'InvokeBuild')) {
        try {
            Write-Verbose "Installing InvokeBuild for current user..."
            Install-Module -Name InvokeBuild -Scope CurrentUser -Force -ErrorAction Stop
        } catch {
            throw "Failed to install InvokeBuild: $($_.Exception.Message)"
        }
    }
    Import-Module InvokeBuild -ErrorAction Stop
}

function Invoke-CliStack {
    [CmdletBinding()]
    param(
        [string]$Task = 'Rebuild',
        [string]$Config = 'config/toolstack.config.json',
        [switch]$DryRun,
        [switch]$VerboseLog,
        [switch]$DebugLog,
        [switch]$Force
    )
    
    Ensure-InvokeBuild
    
    # Set environment variables for the build
    $env:CLISTACK_EFFECTIVE_CONFIG = (Resolve-Path -LiteralPath $Config -ErrorAction SilentlyContinue) ?? $Config
    
    if ($DryRun) {
        $env:CLISTACK_DRYRUN = "true"
        Write-Host "[DRY-RUN MODE] No actual changes will be made" -ForegroundColor Yellow
    } else {
        $env:CLISTACK_DRYRUN = "false"
    }
    
    if ($Force) {
        $env:CLISTACK_FORCE = "true"
    } else {
        $env:CLISTACK_FORCE = "false"
    }
    
    $ibArgs = @($Task)
    if ($VerboseLog) { $ibArgs += '--' ; $ibArgs += '-Verbose' }
    if ($DebugLog)   { $ibArgs += '--' ; $ibArgs += '-Debug' }
    
    if ($DryRun) {
        Write-Host "[DRY-RUN] Would invoke: Invoke-Build $($ibArgs -join ' ') with config $Config" -ForegroundColor Cyan
        Write-Host "[DRY-RUN] Continuing to show what would be executed..." -ForegroundColor Cyan
    }
    
    try {
        Invoke-Build @ibArgs
    } finally {
        # Clean up environment variables
        Remove-Item Env:\CLISTACK_DRYRUN -ErrorAction SilentlyContinue
        Remove-Item Env:\CLISTACK_FORCE -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Invoke-CliStack
