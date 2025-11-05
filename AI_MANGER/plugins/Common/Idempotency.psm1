# Idempotency Module
# Provides helpers to ensure tasks can be run multiple times safely

Set-StrictMode -Version Latest

function Test-StateFile {
    <#
    .SYNOPSIS
    Check if a state file exists and is valid
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [int]$MaxAgeMinutes = -1
    )
    
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    
    if ($MaxAgeMinutes -gt 0) {
        $fileAge = (Get-Date) - (Get-Item $Path).LastWriteTime
        if ($fileAge.TotalMinutes -gt $MaxAgeMinutes) {
            Write-LogDebug "State file is older than $MaxAgeMinutes minutes"
            return $false
        }
    }
    
    return $true
}

function Save-State {
    <#
    .SYNOPSIS
    Save state information to a JSON file
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [hashtable]$State
    )
    
    $stateDir = Split-Path -Path $Path -Parent
    if ($stateDir -and -not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    }
    
    $State.Timestamp = Get-Date -Format "o"
    $State | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
    
    Write-LogDebug "State saved to: $Path"
}

function Get-State {
    <#
    .SYNOPSIS
    Load state information from a JSON file
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-LogDebug "State file not found: $Path"
        return $null
    }
    
    try {
        $content = Get-Content -Path $Path -Raw -Encoding UTF8
        $state = $content | ConvertFrom-Json -AsHashtable
        Write-LogDebug "State loaded from: $Path"
        return $state
    } catch {
        Write-LogWarning "Failed to load state from $Path : $($_.Exception.Message)"
        return $null
    }
}

function Test-ShouldSkipTask {
    <#
    .SYNOPSIS
    Determine if a task should be skipped based on state
    .DESCRIPTION
    Checks if task was completed recently and inputs haven't changed
    #>
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,
        
        [string]$StateDir = "$env:LOCALAPPDATA\CLI_State",
        
        [int]$MaxAgeMinutes = -1,
        
        [hashtable]$CurrentInputs = @{},
        
        [switch]$Force
    )
    
    if ($Force) {
        Write-LogDebug "Force flag set, not skipping task"
        return $false
    }
    
    $stateFile = Join-Path $StateDir "$TaskName.state.json"
    
    if (-not (Test-StateFile -Path $stateFile -MaxAgeMinutes $MaxAgeMinutes)) {
        Write-LogDebug "Task state not found or expired"
        return $false
    }
    
    $savedState = Get-State -Path $stateFile
    if (-not $savedState) {
        return $false
    }
    
    # Check if inputs have changed
    if ($CurrentInputs.Count -gt 0 -and $savedState.Inputs) {
        $savedInputsJson = $savedState.Inputs | ConvertTo-Json -Compress
        $currentInputsJson = $CurrentInputs | ConvertTo-Json -Compress
        
        if ($savedInputsJson -ne $currentInputsJson) {
            Write-LogDebug "Task inputs have changed since last run"
            return $false
        }
    }
    
    Write-LogInfo "Task '$TaskName' was completed recently and inputs unchanged, skipping"
    return $true
}

function Save-TaskCompletion {
    <#
    .SYNOPSIS
    Mark task as completed with current inputs
    #>
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,
        
        [string]$StateDir = "$env:LOCALAPPDATA\CLI_State",
        
        [hashtable]$Inputs = @{},
        
        [hashtable]$Outputs = @{}
    )
    
    $stateFile = Join-Path $StateDir "$TaskName.state.json"
    
    $state = @{
        TaskName = $TaskName
        Completed = $true
        Inputs = $Inputs
        Outputs = $Outputs
    }
    
    Save-State -Path $stateFile -State $state
    Write-LogDebug "Task completion recorded: $TaskName"
}

function Test-PackageInstalled {
    <#
    .SYNOPSIS
    Check if a package is already installed
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,
        
        [Parameter(Mandatory)]
        [ValidateSet("pipx", "npm")]
        [string]$Manager,
        
        [string]$Version = $null
    )
    
    Write-LogDebug "Checking if $PackageName is installed via $Manager"
    
    switch ($Manager) {
        "pipx" {
            $result = cmd /c "pipx list" 2>&1
            $installed = $result -match [regex]::Escape($PackageName)
            
            if ($installed -and $Version) {
                # Check version if specified
                $versionLine = $result | Where-Object { $_ -match [regex]::Escape($PackageName) }
                $installed = $versionLine -match [regex]::Escape($Version)
            }
            
            return $installed
        }
        "npm" {
            $result = cmd /c "npm list -g $PackageName --depth=0" 2>&1
            $installed = $LASTEXITCODE -eq 0
            
            if ($installed -and $Version) {
                $installed = $result -match [regex]::Escape($Version)
            }
            
            return $installed
        }
    }
    
    return $false
}

function Clear-StateFiles {
    <#
    .SYNOPSIS
    Clear all state files (useful for debugging)
    #>
    param(
        [string]$StateDir = "$env:LOCALAPPDATA\CLI_State",
        [string]$Pattern = "*.state.json"
    )
    
    if (Test-Path -LiteralPath $StateDir) {
        $files = Get-ChildItem -Path $StateDir -Filter $Pattern
        foreach ($file in $files) {
            Remove-Item -Path $file.FullName -Force
            Write-LogDebug "Removed state file: $($file.Name)"
        }
    }
}

Export-ModuleMember -Function Test-StateFile, Save-State, Get-State, 
                               Test-ShouldSkipTask, Save-TaskCompletion,
                               Test-PackageInstalled, Clear-StateFiles
