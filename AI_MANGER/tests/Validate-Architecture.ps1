#!/usr/bin/env pwsh
<#
.SYNOPSIS
Validation script for architecture hardening implementation

.DESCRIPTION
Tests the new architecture modules without requiring full build system dependencies
#>

param(
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Architecture Hardening Validation ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Module imports
Write-Host "[1/6] Testing module imports..." -ForegroundColor Yellow
try {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $commonDir = Join-Path $repoRoot "plugins/Common"
    Import-Module (Join-Path $commonDir "Logger.psm1") -Force -Global
    Import-Module (Join-Path $commonDir "ErrorHandler.psm1") -Force -Global
    Import-Module (Join-Path $commonDir "Idempotency.psm1") -Force -Global
    Import-Module (Join-Path $commonDir "Plugin.Interfaces.psm1") -Force -Global
    Write-Host "  ✓ All modules imported successfully" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to import modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 2: Logger initialization
Write-Host "[2/6] Testing logger initialization..." -ForegroundColor Yellow
try {
    Initialize-Logger -Level "info"
    Write-LogInfo "Logger test message"
    Write-LogDebug "Debug message (should not appear)"
    Write-LogSuccess "Logger working"
    Write-Host "  ✓ Logger initialized and working" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Logger test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 3: Error handling
Write-Host "[3/6] Testing error handling..." -ForegroundColor Yellow
try {
    $result = Invoke-SafeCommand -Command "echo test" -DryRun
    if ($result.Success -and $result.ExitCode -eq 0) {
        Write-Host "  ✓ Error handling working (dry-run)" -ForegroundColor Green
    } else {
        throw "Unexpected result from Invoke-SafeCommand"
    }
} catch {
    Write-Host "  ✗ Error handling test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 4: Idempotency
Write-Host "[4/6] Testing idempotency..." -ForegroundColor Yellow
try {
    $tempDir = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) { $env:TEMP } else { "/tmp" }
    $testStateDir = Join-Path $tempDir "validation_test_$(Get-Random)"
    
    $shouldSkip1 = Test-ShouldSkipTask -TaskName "ValidationTest" -StateDir $testStateDir
    if ($shouldSkip1) {
        throw "Should not skip on first run"
    }
    
    Save-TaskCompletion -TaskName "ValidationTest" -StateDir $testStateDir -Inputs @{ test = "data" }
    
    $shouldSkip2 = Test-ShouldSkipTask -TaskName "ValidationTest" -StateDir $testStateDir -CurrentInputs @{ test = "data" }
    if (-not $shouldSkip2) {
        throw "Should skip on second run"
    }
    
    # Clean up
    if (Test-Path $testStateDir) {
        Remove-Item -Path $testStateDir -Recurse -Force
    }
    
    Write-Host "  ✓ Idempotency working" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Idempotency test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 5: Configuration schema
Write-Host "[5/6] Testing configuration schema..." -ForegroundColor Yellow
try {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $schemaPath = Join-Path $repoRoot "config/toolstack.schema.json"
    if (-not (Test-Path $schemaPath)) {
        throw "Schema file not found"
    }
    
    $schema = Get-Content $schemaPath -Raw | ConvertFrom-Json
    if (-not $schema.'$schema') {
        throw "Invalid schema structure"
    }
    
    if (-not ($schema.required -contains "ToolsRoot" -and $schema.required -contains "logging")) {
        throw "Required fields not properly defined"
    }
    
    Write-Host "  ✓ Configuration schema valid" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Schema validation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 6: Plugin interfaces
Write-Host "[6/6] Testing plugin interfaces..." -ForegroundColor Yellow
try {
    # Use platform-appropriate path
    $toolsRoot = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) { 
        "C:\Tools" 
    } else { 
        "/opt/tools" 
    }
    
    $testContext = @{
        ToolsRoot = $toolsRoot
        logging = @{
            level = "info"
        }
    }
    
    Initialize-PluginContext -Context $testContext
    
    # Test without context (should check environment variable)
    $env:CLISTACK_DRYRUN = "false"
    $isDryRun = Get-IsDryRun
    if ($isDryRun -ne $false) {
        throw "Unexpected dry-run state"
    }
    
    Write-Host "  ✓ Plugin interfaces working" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Plugin interface test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== All Validation Tests Passed! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Architecture hardening implementation is working correctly." -ForegroundColor Cyan
Write-Host "Key features validated:" -ForegroundColor Cyan
Write-Host "  • Standardized logging with multiple levels" -ForegroundColor White
Write-Host "  • Error handling with standard exit codes" -ForegroundColor White
Write-Host "  • Idempotency with state management" -ForegroundColor White
Write-Host "  • Dry-run support" -ForegroundColor White
Write-Host "  • JSON schema validation" -ForegroundColor White
Write-Host "  • Plugin interfaces" -ForegroundColor White
Write-Host ""

exit 0
