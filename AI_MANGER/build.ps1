#requires -Modules InvokeBuild
param()
Set-StrictMode -Version Latest

# Load configuration
$ConfigPath = Join-Path $PSScriptRoot 'config/toolstack.config.json'
if (-not (Test-Path $ConfigPath)) {
    throw "Missing config/toolstack.config.json"
}
$Context = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable

# Discover and load plugins
$PluginsDir = Join-Path $PSScriptRoot 'plugins'
$PluginDirs = Get-ChildItem -Path $PluginsDir -Directory | Where-Object { $_.Name -ne 'Common' }

foreach ($dir in $PluginDirs) {
    $pluginFile = Join-Path $dir.FullName 'Plugin.psm1'
    if (Test-Path $pluginFile) {
        Write-Verbose "Loading plugin: $($dir.Name)"
        $importedModule = Import-Module $pluginFile -Force -PassThru -ErrorAction SilentlyContinue
        if ($importedModule) {
            try {
                $registerFunc = Get-Command -Name 'Register-Plugin' -Module $importedModule.Name -ErrorAction SilentlyContinue
                if ($registerFunc) {
                    & $registerFunc -Context $Context -BuildRoot $PSScriptRoot
                }
            } catch {
                Write-Warning "Failed to register plugin $($dir.Name): $_"
            }
        }
    }
}

# Default task
task . Default

# Default invokes Rebuild
task Default Rebuild

# Simple rebuild placeholder task
task Rebuild {
    Write-Host "Rebuild: placeholder (lint/pack can be added here)."
}
