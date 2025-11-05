Describe 'Architecture Integration Tests' {
    BeforeAll {
        # Import required modules
        $commonDir = Join-Path $PSScriptRoot "../../plugins/Common"
        Import-Module (Join-Path $commonDir "Logger.psm1") -Force -Global
        Import-Module (Join-Path $commonDir "ErrorHandler.psm1") -Force -Global
        Import-Module (Join-Path $commonDir "Idempotency.psm1") -Force -Global
        Import-Module (Join-Path $commonDir "Plugin.Interfaces.psm1") -Force -Global
        
        # Initialize logger for tests
        Initialize-Logger -Level "debug"
        
        # Create test config
        $script:TestConfig = @{
            ToolsRoot = "C:\Tools"
            logging = @{
                level = "info"
            }
            NpmGlobal = @("eslint", "prettier")
            PipxApps = @("black", "ruff")
        }
    }
    
    AfterAll {
        Remove-Module Logger -ErrorAction SilentlyContinue
        Remove-Module ErrorHandler -ErrorAction SilentlyContinue
        Remove-Module Idempotency -ErrorAction SilentlyContinue
        Remove-Module Plugin.Interfaces -ErrorAction SilentlyContinue
    }
    
    Context 'Plugin.Interfaces' {
        It 'Should export Invoke-Quiet function' {
            Get-Command Invoke-Quiet -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It 'Should export Get-IsDryRun function' {
            Get-Command Get-IsDryRun -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It 'Should export Initialize-PluginContext function' {
            Get-Command Initialize-PluginContext -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It 'Should initialize plugin context with config' {
            { Initialize-PluginContext -Context $TestConfig } | Should -Not -Throw
        }
    }
    
    Context 'Get-IsDryRun' {
        It 'Should return false when not in dry-run mode' {
            $env:CLISTACK_DRYRUN = "false"
            $result = Get-IsDryRun
            $result | Should -Be $false
        }
        
        It 'Should return true when in dry-run mode' {
            $env:CLISTACK_DRYRUN = "true"
            $result = Get-IsDryRun
            $result | Should -Be $true
        }
        
        It 'Should use context DryRun flag' {
            $env:CLISTACK_DRYRUN = "false"
            $context = @{ DryRun = $true }
            $result = Get-IsDryRun -Context $context
            $result | Should -Be $true
        }
    }
    
    Context 'Invoke-Quiet with DryRun' {
        It 'Should execute command normally' {
            { Invoke-Quiet -Command "echo test" } | Should -Not -Throw
        }
        
        It 'Should skip command in dry-run mode' {
            { Invoke-Quiet -Command "echo test" -DryRun } | Should -Not -Throw
        }
    }
    
    Context 'End-to-End Idempotency' {
        It 'Should allow task to skip on second run' {
            $tempDir = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) { $env:TEMP } else { "/tmp" }
            $testStateDir = Join-Path $tempDir "test_integration_$(Get-Random)"
            $taskName = "E2ETest"
            $inputs = @{ TestParam = "TestValue" }
            
            try {
                # First run - should not skip
                $shouldSkip1 = Test-ShouldSkipTask -TaskName $taskName -StateDir $testStateDir -CurrentInputs $inputs
                $shouldSkip1 | Should -Be $false
                
                # Mark as completed
                Save-TaskCompletion -TaskName $taskName -StateDir $testStateDir -Inputs $inputs
                
                # Second run - should skip
                $shouldSkip2 = Test-ShouldSkipTask -TaskName $taskName -StateDir $testStateDir -CurrentInputs $inputs
                $shouldSkip2 | Should -Be $true
            } finally {
                # Clean up
                if (Test-Path $testStateDir) {
                    Remove-Item -Path $testStateDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    
    Context 'Error Handling Integration' {
        It 'Should handle command failure with proper error result' {
            $cmd = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) { "cmd /c exit 1" } else { "sh -c 'exit 1'" }
            $result = Invoke-SafeCommand -Command $cmd -ErrorMessage "Test error" -ContinueOnError
            $result.Success | Should -Be $false
        }
        
        It 'Should chain error handling with logging' {
            { 
                $result = Invoke-SafeCommand -Command "echo success" -ErrorMessage "Should not fail"
                if (-not $result.Success) {
                    Write-LogError "Command failed"
                } else {
                    Write-LogSuccess "Command succeeded"
                }
            } | Should -Not -Throw
        }
    }
    
    Context 'Schema Validation' {
        It 'Should have valid toolstack schema file' {
            $schemaPath = Join-Path $PSScriptRoot "../../config/toolstack.schema.json"
            Test-Path $schemaPath | Should -Be $true
            
            $schema = Get-Content $schemaPath -Raw | ConvertFrom-Json
            $schema.'$schema' | Should -Not -BeNullOrEmpty
            $schema.properties | Should -Not -BeNullOrEmpty
        }
        
        It 'Schema should define required fields' {
            $schemaPath = Join-Path $PSScriptRoot "../../config/toolstack.schema.json"
            $schema = Get-Content $schemaPath -Raw | ConvertFrom-Json
            
            $schema.required | Should -Contain "ToolsRoot"
            $schema.required | Should -Contain "logging"
        }
        
        It 'Schema should define logging properties' {
            $schemaPath = Join-Path $PSScriptRoot "../../config/toolstack.schema.json"
            $schema = Get-Content $schemaPath -Raw | ConvertFrom-Json
            
            $schema.properties.logging | Should -Not -BeNullOrEmpty
            $schema.properties.logging.properties.level | Should -Not -BeNullOrEmpty
        }
    }
}
