# Architecture Hardening Guide

This document describes the architecture improvements implemented in issue #3, including standardized logging, error handling, idempotency, and dry-run support.

## Overview

The architecture hardening effort implements the following key improvements:

1. **Finalized Config Schema** - Complete JSON schema validation for configuration files
2. **Standardized Logging** - Consistent logging across all plugins with configurable levels
3. **Error Handling** - Standard error codes and error handling patterns
4. **Idempotency** - Tasks can be run multiple times safely without side effects
5. **Dry-Run Support** - Test task execution without making actual changes

## Configuration Schema

### Location
- `config/toolstack.schema.json` - Main configuration schema
- `config/clistack.schema.json` - CLI stack specific schema

### Key Features
- JSON Schema Draft 07 compliant
- Validates all configuration properties
- Defines required fields: `ToolsRoot`, `logging`
- Supports logging configuration with levels: `debug`, `info`, `warning`, `error`

### Example Configuration
```json
{
  "ToolsRoot": "C:\\Tools",
  "logging": {
    "level": "info",
    "logFile": "C:\\Tools\\logs\\clistack.log"
  },
  "tasks": {
    "bootstrap": { "enabled": true }
  }
}
```

## Logging Module (`plugins/Common/Logger.psm1`)

### Features
- Hierarchical log levels: `debug`, `info`, `warning`, `error`
- Console output with color coding
- Optional file logging
- Timestamp on all log entries
- Automatic log level filtering

### Usage

#### Initialize Logger
```powershell
# Initialize with default level (info)
Initialize-Logger

# Initialize with specific level
Initialize-Logger -Level "debug"

# Initialize with log file
Initialize-Logger -Level "info" -LogFilePath "C:\Tools\logs\app.log"
```

#### Logging Functions
```powershell
# Debug level (only shown when level is debug)
Write-LogDebug "Detailed debugging information"

# Info level (general information)
Write-LogInfo "Starting task..."

# Warning level (potential issues)
Write-LogWarning "Configuration not optimal"

# Error level (errors that need attention)
Write-LogError "Failed to connect to service"

# Success message (info level with green color and checkmark)
Write-LogSuccess "Task completed successfully"
```

### Log Output Format
```
[2025-11-05 05:42:49] DEBUG   Debug message
[2025-11-05 05:42:49] INFO    Info message
[2025-11-05 05:42:49] WARNING Warning message
[2025-11-05 05:42:49] ERROR   Error message
[2025-11-05 05:42:49] INFO    ✓ Success message
```

## Error Handling Module (`plugins/Common/ErrorHandler.psm1`)

### Standard Exit Codes
```powershell
Success           = 0   # Operation completed successfully
GeneralError      = 1   # Generic error
InvalidConfig     = 2   # Configuration validation failed
MissingDependency = 3   # Required dependency not found
CommandFailed     = 4   # External command failed
ValidationFailed  = 5   # Input validation failed
NotImplemented    = 6   # Feature not implemented
PermissionDenied  = 7   # Insufficient permissions
Timeout          = 8   # Operation timed out
```

### Key Functions

#### Invoke-SafeCommand
Execute commands with error handling and logging:

```powershell
# Execute command with error handling
$result = Invoke-SafeCommand -Command "npm install -g eslint"

# Execute with custom error message
$result = Invoke-SafeCommand `
    -Command "npm install -g eslint" `
    -ErrorMessage "Failed to install eslint"

# Continue on error (don't throw)
$result = Invoke-SafeCommand `
    -Command "npm install -g package" `
    -ContinueOnError

# Dry-run mode (simulate execution)
$result = Invoke-SafeCommand `
    -Command "npm install -g eslint" `
    -DryRun
```

Result object:
```powershell
@{
    Success = $true/$false
    Output = "command output"
    ExitCode = 0
}
```

#### Test-Prerequisite
Check if prerequisites are available:

```powershell
# Check if command exists
$exists = Test-Prerequisite -Name "npm" -Type Command

# Check if path exists
$exists = Test-Prerequisite -Name "C:\Tools" -Type Path

# Throw error if missing
Test-Prerequisite -Name "git" -Type Command -ThrowOnFailure
```

#### Error Result Objects
```powershell
# Create error result
$error = New-ErrorResult `
    -Message "Configuration is invalid" `
    -ExitCodeName "InvalidConfig"

# Create success result
$success = New-SuccessResult `
    -Message "Task completed" `
    -Data @{ ItemsProcessed = 42 }
```

#### Invoke-WithRetry
Retry operations with exponential backoff:

```powershell
Invoke-WithRetry `
    -ScriptBlock { Install-Package "some-package" } `
    -MaxAttempts 3 `
    -DelaySeconds 2 `
    -ErrorMessage "Failed to install package after retries"
```

## Idempotency Module (`plugins/Common/Idempotency.psm1`)

### Purpose
Ensures tasks can be run multiple times safely without unwanted side effects or duplicate work.

### Key Concepts
- **State Files**: JSON files tracking task completion
- **Input Tracking**: Detects when inputs change
- **Time-based Expiry**: Optional age-based invalidation
- **Force Override**: Skip idempotency checks when needed

### Functions

#### Test-ShouldSkipTask
Determine if a task should be skipped:

```powershell
# Check if task should skip
$shouldSkip = Test-ShouldSkipTask `
    -TaskName "NpmInstall" `
    -CurrentInputs @{ packages = "eslint,prettier" }

if ($shouldSkip) {
    Write-LogInfo "Task already completed, skipping"
    return
}
```

With age-based expiry:
```powershell
# Skip only if completed within last 60 minutes
$shouldSkip = Test-ShouldSkipTask `
    -TaskName "NpmInstall" `
    -CurrentInputs @{ packages = "eslint,prettier" } `
    -MaxAgeMinutes 60
```

#### Save-TaskCompletion
Record task completion:

```powershell
# Save completion state
Save-TaskCompletion `
    -TaskName "NpmInstall" `
    -Inputs @{ packages = "eslint,prettier" } `
    -Outputs @{ installed = 2; failed = 0 }
```

#### Test-PackageInstalled
Check if packages are already installed:

```powershell
# Check npm package
if (Test-PackageInstalled -PackageName "eslint" -Manager "npm") {
    Write-LogDebug "Package already installed"
}

# Check pipx package
if (Test-PackageInstalled -PackageName "black" -Manager "pipx") {
    Write-LogDebug "Package already installed"
}

# Check specific version
$installed = Test-PackageInstalled `
    -PackageName "eslint" `
    -Manager "npm" `
    -Version "9.39.0"
```

### State File Location
Default: `$env:LOCALAPPDATA\CLI_State` (Windows) or `~/.local/state/cli` (Linux/macOS)

State files: `{TaskName}.state.json`

### State File Format
```json
{
  "TaskName": "NpmInstall",
  "Completed": true,
  "Inputs": {
    "packages": "eslint,prettier"
  },
  "Outputs": {
    "installed": 2,
    "failed": 0
  },
  "Timestamp": "2025-11-05T05:42:49.123Z"
}
```

## Dry-Run Support

### Overview
Dry-run mode allows testing task execution without making actual changes to the system.

### Enabling Dry-Run

#### Command Line
```powershell
# Using Invoke-CliStack
Invoke-CliStack -Task "NpmInstall" -DryRun

# Using build.ps1 (if extended)
Invoke-Build -File .\build.ps1 NpmInstall -DryRun
```

#### Environment Variable
```powershell
$env:CLISTACK_DRYRUN = "true"
Invoke-Build -File .\build.ps1 NpmInstall
```

### Implementation in Plugins
```powershell
function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force
  
  Initialize-PluginContext -Context $Context
  
  task MyTask {
    Write-LogInfo "Running MyTask"
    
    # Get dry-run flag
    $isDryRun = Get-IsDryRun -Context $Context
    
    # Use with Invoke-SafeCommand
    Invoke-SafeCommand -Command "npm install -g eslint" -DryRun:$isDryRun
    
    # Use with legacy Invoke-Quiet
    Invoke-Quiet -Command "npm install -g prettier" -DryRun:$isDryRun
    
    # Manual dry-run check
    if ($isDryRun) {
      Write-LogInfo "[DRY-RUN] Would create directory: C:\Tools\bin"
    } else {
      New-Item -ItemType Directory -Path "C:\Tools\bin"
    }
  }
}
```

## Plugin Integration

### Updated Plugin Template
```powershell
# plugins/MyPlugin/Plugin.psm1
param()

function Register-Plugin {
  param($Context, $BuildRoot)
  
  # Import common interfaces
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force
  
  # Initialize plugin context (sets up logging)
  Initialize-PluginContext -Context $Context
  
  task MyTask {
    Write-LogInfo "==> Running MyTask"
    
    # Get dry-run and force flags
    $isDryRun = Get-IsDryRun -Context $Context
    $isForce = $env:CLISTACK_FORCE -eq "true"
    
    # Define task inputs for idempotency
    $inputs = @{
      param1 = $Context.MyParam1
      param2 = $Context.MyParam2
    }
    
    # Check if should skip (idempotency)
    if (Test-ShouldSkipTask -TaskName "MyTask" -CurrentInputs $inputs -Force:$isForce) {
      Write-LogSuccess "MyTask already completed with current inputs"
      return
    }
    
    # Check prerequisites
    if (-not (Test-Prerequisite -Name "npm" -Type Command -ThrowOnFailure)) {
      return
    }
    
    # Execute work with error handling
    try {
      $result = Invoke-SafeCommand `
        -Command "npm install -g my-package" `
        -DryRun:$isDryRun `
        -ErrorMessage "Failed to install package"
      
      if ($result.Success) {
        Write-LogSuccess "Package installed successfully"
      }
      
      # Save completion state
      if (-not $isDryRun) {
        Save-TaskCompletion -TaskName "MyTask" -Inputs $inputs
      }
      
    } catch {
      Write-LogError "MyTask failed: $($_.Exception.Message)"
      throw
    }
  }
}

Export-ModuleMember -Function Register-Plugin
```

## Best Practices

### Logging
1. Use appropriate log levels:
   - `Debug`: Detailed internal state, variable values
   - `Info`: Progress updates, task starts/completions
   - `Warning`: Non-critical issues, fallback actions
   - `Error`: Failures requiring attention
2. Log task start with `Write-LogInfo "==> Task name"`
3. Log completions with `Write-LogSuccess`
4. Include context in error messages

### Error Handling
1. Always use `Invoke-SafeCommand` for external commands
2. Use `-ContinueOnError` for optional operations
3. Provide meaningful error messages
4. Return structured result objects
5. Validate prerequisites before executing tasks

### Idempotency
1. Define clear task inputs
2. Use `Test-ShouldSkipTask` at task start
3. Call `Save-TaskCompletion` on success
4. Check package installation before reinstalling
5. Use appropriate cache expiry times

### Dry-Run
1. Always support dry-run in plugins
2. Log what would be done: `[DRY-RUN] Would execute: ...`
3. Pass `$isDryRun` to `Invoke-SafeCommand`
4. Don't save state in dry-run mode
5. Don't skip idempotency checks in dry-run (show what would happen)

## Testing

### Running Tests
```powershell
# Run all architecture tests
Invoke-Pester -Path tests/Unit/Architecture.Tests.ps1
Invoke-Pester -Path tests/Integration/Architecture.Tests.ps1

# Run specific test
Invoke-Pester -Path tests/Unit/Architecture.Tests.ps1 -Tag "Logger"

# With detailed output
Invoke-Pester -Path tests/Unit/Architecture.Tests.ps1 -Output Detailed
```

### Test Coverage
- Logger: Initialization, log levels, filtering, file output
- ErrorHandler: Exit codes, command execution, prerequisites, retries
- Idempotency: State management, task skipping, package checking
- Integration: End-to-end workflows, schema validation

## Migration Guide

### Updating Existing Plugins

1. **Add Plugin Context Initialization**
   ```powershell
   # At the start of Register-Plugin
   Initialize-PluginContext -Context $Context
   ```

2. **Replace Write-Host with Logging**
   ```powershell
   # Before
   Write-Host "Installing packages" -ForegroundColor Cyan
   
   # After
   Write-LogInfo "==> Installing packages"
   ```

3. **Replace Invoke-Quiet with Invoke-SafeCommand**
   ```powershell
   # Before
   Invoke-Quiet "npm install -g eslint"
   
   # After
   $isDryRun = Get-IsDryRun -Context $Context
   Invoke-SafeCommand -Command "npm install -g eslint" -DryRun:$isDryRun
   ```

4. **Add Idempotency**
   ```powershell
   # Define inputs
   $inputs = @{ packages = ($Context.NpmGlobal -join ",") }
   
   # Check at task start
   if (Test-ShouldSkipTask -TaskName "NpmInstall" -CurrentInputs $inputs) {
     return
   }
   
   # ... do work ...
   
   # Save on completion
   Save-TaskCompletion -TaskName "NpmInstall" -Inputs $inputs
   ```

5. **Add Prerequisites Check**
   ```powershell
   if (-not (Test-Prerequisite -Name "npm" -Type Command)) {
     Write-LogError "npm not found"
     return
   }
   ```

## Troubleshooting

### Clear State Files
```powershell
# Import module
Import-Module .\plugins\Common\Idempotency.psm1

# Clear all state files
Clear-StateFiles

# Clear specific pattern
Clear-StateFiles -Pattern "NpmInstall*.state.json"
```

### Debug Logging
```powershell
# Set debug level in config
{
  "logging": { "level": "debug" }
}

# Or via environment
$env:CLISTACK_LOG_LEVEL = "debug"
```

### Force Task Execution
```powershell
# Skip idempotency checks
$env:CLISTACK_FORCE = "true"
Invoke-Build -File .\build.ps1 MyTask
```

## Performance Considerations

1. **State Files**: Minimal overhead, JSON files are small (~1KB)
2. **Idempotency Checks**: Fast file existence checks
3. **Logging**: Console output is buffered, file I/O is async
4. **Package Checks**: Cached results within task execution

## Cross-Platform Support

All modules support:
- Windows (PowerShell 5.1 and 7+)
- Linux (PowerShell 7+)
- macOS (PowerShell 7+)

Platform-specific handling:
- Command execution (cmd vs sh)
- Path separators
- Temporary directories
- Environment variables
