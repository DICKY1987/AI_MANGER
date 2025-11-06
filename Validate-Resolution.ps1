#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates the conflict resolution for PR #9
.DESCRIPTION
    This script runs a series of validation tests to ensure the merged code
    is syntactically correct and maintains functionality from both branches.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== PR #9 Conflict Resolution Validation ===" -ForegroundColor Cyan
Write-Host ""

$tests = @()
$passed = 0
$failed = 0

# Change to AI_MANGER directory
$scriptLocation = $MyInvocation.MyCommand.Path
if ($scriptLocation) {
    $scriptRoot = Split-Path -Parent $scriptLocation
    $aiMangerPath = Join-Path $scriptRoot "AI_MANGER"
    if (Test-Path $aiMangerPath) {
        Set-Location $aiMangerPath
        Write-Host "Working directory: $aiMangerPath" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "Working directory: $PWD" -ForegroundColor Gray
        Write-Host ""
    }
} else {
    Write-Host "Working directory: $PWD" -ForegroundColor Gray
    Write-Host ""
}

# Test 1: Module Manifest
Write-Host "Test 1: Validating module manifest..." -NoNewline
try {
    $manifest = Test-ModuleManifest -Path "module/CliStack.psd1" -ErrorAction Stop
    if ($manifest.Version -eq '0.1.0' -and $manifest.PowerShellVersion -eq '7.0') {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " ✗ FAIL (version mismatch)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 2: Module Import
Write-Host "Test 2: Importing module..." -NoNewline
try {
    Import-Module "./module/CliStack.psd1" -Force -ErrorAction Stop
    $cmd = Get-Command Invoke-CliStack -ErrorAction Stop
    if ($cmd) {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 3: Module has required functions
Write-Host "Test 3: Checking exported functions..." -NoNewline
try {
    $module = Get-Module CliStack
    if ($module.ExportedFunctions.Keys -contains 'Invoke-CliStack') {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " ✗ FAIL (Invoke-CliStack not exported)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 4: Build script syntax
Write-Host "Test 4: Validating build script syntax..." -NoNewline
try {
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "build.ps1" -Raw), [ref]$null)
    Write-Host " ✓ PASS" -ForegroundColor Green
    $passed++
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 5: Build script has Health.Check task
Write-Host "Test 5: Checking for Health.Check task..." -NoNewline
try {
    $buildContent = Get-Content "build.ps1" -Raw
    if ($buildContent -match "task\s+'Health\.Check'") {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " ✗ FAIL (Health.Check task not found)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 6: Build script has plugin loading
Write-Host "Test 6: Checking for plugin system..." -NoNewline
try {
    $buildContent = Get-Content "build.ps1" -Raw
    if ($buildContent -match "Register-Plugin" -and $buildContent -match "plugins") {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " ✗ FAIL (Plugin system not found)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 7: CliStack.psm1 has Force parameter
Write-Host "Test 7: Checking for Force parameter..." -NoNewline
try {
    $moduleContent = Get-Content "module/CliStack.psm1" -Raw
    if ($moduleContent -match '\[switch\]\$Force') {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " ✗ FAIL (Force parameter not found)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 8: CliStack.psm1 has PSGallery registration
Write-Host "Test 8: Checking for PSGallery registration..." -NoNewline
try {
    $moduleContent = Get-Content "module/CliStack.psm1" -Raw
    if ($moduleContent -match "Register-PSRepository" -and $moduleContent -match "PSGallery") {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " ✗ FAIL (PSGallery registration not found)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 9: Config files exist and are valid JSON
Write-Host "Test 9: Validating configuration files..." -NoNewline
try {
    $config = Get-Content "config/toolstack.config.json" -Raw | ConvertFrom-Json
    $schema = Get-Content "config/toolstack.schema.json" -Raw | ConvertFrom-Json
    $cliSchema = Get-Content "config/clistack.schema.json" -Raw | ConvertFrom-Json
    
    if ($config.Observability -and $config.reportsDir) {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " ✗ FAIL (missing required config fields)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 10: Install script has GitHub download capability
Write-Host "Test 10: Checking installer capabilities..." -NoNewline
try {
    $installerContent = Get-Content "scripts/Install-CliStack.ps1" -Raw
    if ($installerContent -match "Get-ModuleFromGitHub" -and $installerContent -match "Invoke-WebRequest") {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " ✗ FAIL (GitHub download not found)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 11: Sign script has certificate cleanup
Write-Host "Test 11: Checking certificate cleanup..." -NoNewline
try {
    $signContent = Get-Content "scripts/Sign-Files.ps1" -Raw
    if ($signContent -match "Remove-Item.*Thumbprint") {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " ✗ FAIL (Certificate cleanup not found)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Test 12: Required plugin files exist
Write-Host "Test 12: Checking plugin files..." -NoNewline
try {
    $requiredPlugins = @(
        "plugins/Common/Plugin.Interfaces.psm1",
        "plugins/HealthCheck/Plugin.psm1",
        "plugins/NpmTools/Plugin.psm1",
        "plugins/PipxTools/Plugin.psm1"
    )
    
    $allExist = $true
    foreach ($plugin in $requiredPlugins) {
        if (-not (Test-Path $plugin)) {
            $allExist = $false
            break
        }
    }
    
    if ($allExist) {
        Write-Host " ✓ PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host " ✗ FAIL (some plugin files missing)" -ForegroundColor Red
        $failed++
    }
} catch {
    Write-Host " ✗ FAIL ($_)" -ForegroundColor Red
    $failed++
}

# Summary
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failed -eq 0) {
    Write-Host "✓ All tests passed! The conflict resolution is valid." -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Some tests failed. Please review the resolution." -ForegroundColor Red
    exit 1
}
