#requires -Modules InvokeBuild
param()
Set-StrictMode -Version Latest

# Default task
task . Default

# Default invokes Rebuild
task Default Rebuild

# Simple rebuild placeholder task
task Rebuild {
    Write-Host "Rebuild: placeholder (lint/pack can be added here)."
}

# Health check that verifies module import and config presence
task 'Health.Check' {
    Write-Host "Running health checks..."
    if (-not (Test-Path -LiteralPath 'config/toolstack.config.json')) {
        throw "Missing config/toolstack.config.json"
    }
    Import-Module -Name (Join-Path $PSScriptRoot 'module/CliStack.psd1') -Force
    Invoke-CliStack -Task Rebuild -Config 'config/toolstack.config.json' -DryRun
    Write-Host "Health.Check passed."
}
