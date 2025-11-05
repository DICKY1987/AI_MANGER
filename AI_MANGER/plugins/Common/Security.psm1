# Common Security Module
# Provides secure command execution and input validation

Set-StrictMode -Version Latest

function Test-SafeString {
    <#
    .SYNOPSIS
    Validates that a string is safe for command execution
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Value,
        
        [ValidateSet("Path", "PackageName", "General")]
        [string]$Type = "General"
    )
    
    switch ($Type) {
        "Path" {
            # Allow common path characters: letters, numbers, backslash, forward slash, colon, dash, underscore, dot, space
            return $Value -match '^[a-zA-Z0-9\\/:\-_\. ]+$'
        }
        "PackageName" {
            # Package names: letters, numbers, @, /, -, _, .
            return $Value -match '^[@a-zA-Z0-9/\-_.]+$'
        }
        "General" {
            # Block shell metacharacters and command separators
            $dangerousChars = '[$;`&|<>{}()!*?~^]'
            return $Value -notmatch $dangerousChars
        }
    }
}

function Invoke-SecureCommand {
    <#
    .SYNOPSIS
    Execute command securely with validation
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        
        [string[]]$Arguments = @(),
        
        [switch]$DryRun
    )
    
    if ($DryRun) {
        $argStr = if ($Arguments) { " $($Arguments -join ' ')" } else { "" }
        Write-LogInfo "[DRY-RUN] Would execute: $Command$argStr"
        return @{ Success = $true; Output = ""; ExitCode = 0 }
    }
    
    Write-LogDebug "Executing: $Command $($Arguments -join ' ')"
    
    try {
        if ($Arguments.Count -gt 0) {
            $process = Start-Process -FilePath $Command -ArgumentList $Arguments -Wait -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP/stdout.txt" -RedirectStandardError "$env:TEMP/stderr.txt" -ErrorAction Stop
            $stdout = Get-Content "$env:TEMP/stdout.txt" -Raw -ErrorAction SilentlyContinue
            $stderr = Get-Content "$env:TEMP/stderr.txt" -Raw -ErrorAction SilentlyContinue
            $output = "$stdout$stderr"
            $exitCode = $process.ExitCode
            
            # Clean up temp files
            Remove-Item "$env:TEMP/stdout.txt" -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP/stderr.txt" -Force -ErrorAction SilentlyContinue
        } else {
            $process = Start-Process -FilePath $Command -Wait -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP/stdout.txt" -RedirectStandardError "$env:TEMP/stderr.txt" -ErrorAction Stop
            $stdout = Get-Content "$env:TEMP/stdout.txt" -Raw -ErrorAction SilentlyContinue
            $stderr = Get-Content "$env:TEMP/stderr.txt" -Raw -ErrorAction SilentlyContinue
            $output = "$stdout$stderr"
            $exitCode = $process.ExitCode
            
            # Clean up temp files
            Remove-Item "$env:TEMP/stdout.txt" -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP/stderr.txt" -Force -ErrorAction SilentlyContinue
        }
        
        Write-LogDebug "Command completed with exit code: $exitCode"
        return @{ Success = ($exitCode -eq 0); Output = $output; ExitCode = $exitCode }
        
    } catch {
        Write-LogError "Command execution failed: $($_.Exception.Message)"
        return @{ Success = $false; Output = $_.Exception.Message; ExitCode = 1 }
    }
}

Export-ModuleMember -Function Test-SafeString, Invoke-SecureCommand
