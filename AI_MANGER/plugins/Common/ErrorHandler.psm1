# Common Error Handling Module
# Provides standardized error handling and exit codes

Set-StrictMode -Version Latest

# Standard exit codes
$script:ExitCodes = @{
    Success           = 0
    GeneralError      = 1
    InvalidConfig     = 2
    MissingDependency = 3
    CommandFailed     = 4
    ValidationFailed  = 5
    NotImplemented    = 6
    PermissionDenied  = 7
    Timeout          = 8
}

function Get-ExitCode {
    <#
    .SYNOPSIS
    Get exit code by name
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Success", "GeneralError", "InvalidConfig", "MissingDependency", 
                     "CommandFailed", "ValidationFailed", "NotImplemented", 
                     "PermissionDenied", "Timeout")]
        [string]$Name
    )
    
    return $script:ExitCodes[$Name]
}

function Invoke-SafeCommand {
    <#
    .SYNOPSIS
    Execute command with error handling and logging
    .DESCRIPTION
    Executes a command and handles errors gracefully with proper logging
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        
        [string]$ErrorMessage = "Command failed",
        
        [switch]$DryRun,
        
        [switch]$ContinueOnError
    )
    
    if ($DryRun) {
        Write-LogInfo "[DRY-RUN] Would execute: $Command"
        return @{ Success = $true; Output = ""; ExitCode = 0 }
    }
    
    Write-LogDebug "Executing: $Command"
    
    try {
        $global:LASTEXITCODE = 0
        
        # Cross-platform command execution
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
            $output = cmd /c $Command 2>&1
        } else {
            # On Linux/macOS, use sh
            $output = sh -c $Command 2>&1
        }
        
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -ne 0) {
            if ($ContinueOnError) {
                Write-LogWarning "$ErrorMessage (exit code: $exitCode)"
                Write-LogDebug "Output: $output"
                return @{ Success = $false; Output = $output; ExitCode = $exitCode }
            } else {
                Write-LogError "$ErrorMessage (exit code: $exitCode)"
                Write-LogDebug "Output: $output"
                throw $ErrorMessage
            }
        }
        
        Write-LogDebug "Command completed successfully"
        return @{ Success = $true; Output = $output; ExitCode = 0 }
        
    } catch {
        Write-LogError "$ErrorMessage : $($_.Exception.Message)"
        if (-not $ContinueOnError) {
            throw
        }
        return @{ Success = $false; Output = $_.Exception.Message; ExitCode = 1 }
    }
}

function Test-Prerequisite {
    <#
    .SYNOPSIS
    Test if a prerequisite command or path exists
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [ValidateSet("Command", "Path")]
        [string]$Type = "Command",
        
        [switch]$ThrowOnFailure
    )
    
    $exists = $false
    
    switch ($Type) {
        "Command" {
            $cmd = Get-Command $Name -ErrorAction SilentlyContinue
            $exists = $null -ne $cmd
            if (-not $exists) {
                $message = "Required command not found: $Name"
            }
        }
        "Path" {
            $exists = Test-Path -LiteralPath $Name
            if (-not $exists) {
                $message = "Required path not found: $Name"
            }
        }
    }
    
    if (-not $exists) {
        if ($ThrowOnFailure) {
            Write-LogError $message
            throw $message
        } else {
            Write-LogWarning $message
        }
    }
    
    return $exists
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
    Execute a script block with retry logic
    #>
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [int]$MaxAttempts = 3,
        
        [int]$DelaySeconds = 2,
        
        [string]$ErrorMessage = "Operation failed after retries"
    )
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        
        try {
            Write-LogDebug "Attempt $attempt of $MaxAttempts"
            & $ScriptBlock
            Write-LogDebug "Operation succeeded on attempt $attempt"
            return $true
        } catch {
            $lastError = $_
            Write-LogWarning "Attempt $attempt failed: $($_.Exception.Message)"
            
            if ($attempt -lt $MaxAttempts) {
                Write-LogDebug "Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
    
    Write-LogError "$ErrorMessage : $($lastError.Exception.Message)"
    throw $lastError
}

function New-ErrorResult {
    <#
    .SYNOPSIS
    Create standardized error result object
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [string]$ExitCodeName = "GeneralError",
        
        [object]$Details = $null
    )
    
    return @{
        Success = $false
        Message = $Message
        ExitCode = Get-ExitCode -Name $ExitCodeName
        Details = $Details
        Timestamp = Get-Date -Format "o"
    }
}

function New-SuccessResult {
    <#
    .SYNOPSIS
    Create standardized success result object
    #>
    param(
        [string]$Message = "Operation completed successfully",
        [object]$Data = $null
    )
    
    return @{
        Success = $true
        Message = $Message
        ExitCode = 0
        Data = $Data
        Timestamp = Get-Date -Format "o"
    }
}

Export-ModuleMember -Function Get-ExitCode, Invoke-SafeCommand, Test-Prerequisite, 
                               Invoke-WithRetry, New-ErrorResult, New-SuccessResult
