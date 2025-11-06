# Common Logging Module
# Provides standardized logging functions across all plugins

Set-StrictMode -Version Latest

# Global log level (set from config)
$script:LogLevel = "info"
$script:LogFile = $null

# Log levels with priority
$script:LogLevels = @{
    "debug"   = 0
    "info"    = 1
    "warning" = 2
    "error"   = 3
}

function Initialize-Logger {
    <#
    .SYNOPSIS
    Initialize logger with configuration
    #>
    param(
        [string]$Level = "info",
        [string]$LogFilePath = $null
    )
    
    $script:LogLevel = $Level.ToLower()
    $script:LogFile = $LogFilePath
    
    if ($LogFilePath -and -not (Test-Path (Split-Path $LogFilePath -Parent))) {
        New-Item -ItemType Directory -Force -Path (Split-Path $LogFilePath -Parent) | Out-Null
    }
}

function Write-Log {
    <#
    .SYNOPSIS
    Internal logging function
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter(Mandatory)]
        [ValidateSet("debug", "info", "warning", "error")]
        [string]$Level,
        
        [string]$Color = "White"
    )
    
    # Check if this message should be logged based on log level
    $currentLevelPriority = $script:LogLevels[$script:LogLevel]
    $messageLevelPriority = $script:LogLevels[$Level]
    
    if ($messageLevelPriority -lt $currentLevelPriority) {
        return
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $levelText = $Level.ToUpper().PadRight(7)
    $logMessage = "[$timestamp] $levelText $Message"
    
    # Write to console with color
    Write-Host $logMessage -ForegroundColor $Color
    
    # Write to file if configured
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logMessage -Encoding UTF8
    }
}

function Write-LogDebug {
    <#
    .SYNOPSIS
    Write debug level log message
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level "debug" -Color DarkGray
}

function Write-LogInfo {
    <#
    .SYNOPSIS
    Write info level log message
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level "info" -Color Cyan
}

function Write-LogWarning {
    <#
    .SYNOPSIS
    Write warning level log message
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level "warning" -Color Yellow
}

function Write-LogError {
    <#
    .SYNOPSIS
    Write error level log message
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level "error" -Color Red
}

function Write-LogSuccess {
    <#
    .SYNOPSIS
    Write success message (info level with green color)
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message "✓ $Message" -Level "info" -Color Green
}

Export-ModuleMember -Function Initialize-Logger, Write-LogDebug, Write-LogInfo, Write-LogWarning, Write-LogError, Write-LogSuccess
