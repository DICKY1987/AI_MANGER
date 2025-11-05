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
        [switch]$DebugLog
    )
    Ensure-InvokeBuild
    $env:CLISTACK_EFFECTIVE_CONFIG = (Resolve-Path -LiteralPath $Config -ErrorAction SilentlyContinue) ?? $Config
    $ibArgs = @($Task)
    if ($VerboseLog) { $ibArgs += '--' ; $ibArgs += '-Verbose' }
    if ($DebugLog)   { $ibArgs += '--' ; $ibArgs += '-Debug' }
    if ($DryRun) {
        Write-Host "[DryRun] Would invoke: Invoke-Build $($ibArgs -join ' ') with config $Config"
        return
    }
    Invoke-Build @ibArgs
}
Export-ModuleMember -Function Invoke-CliStack
