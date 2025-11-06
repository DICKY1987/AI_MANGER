Describe 'Logger Module' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot "../../plugins/Common/Logger.psm1"
        Import-Module $modulePath -Force
    }
    
    AfterAll {
        Remove-Module Logger -ErrorAction SilentlyContinue
    }
    
    Context 'Initialize-Logger' {
        It 'Should initialize with default level' {
            { Initialize-Logger } | Should -Not -Throw
        }
        
        It 'Should initialize with specific level' {
            { Initialize-Logger -Level "debug" } | Should -Not -Throw
        }
        
        It 'Should initialize with log file' {
            $tempDir = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) { $env:TEMP } else { "/tmp" }
            $tempFile = Join-Path $tempDir "test_log_$(Get-Random).txt"
            
            try {
                { Initialize-Logger -Level "info" -LogFilePath $tempFile } | Should -Not -Throw
            } finally {
                # Clean up
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    
    Context 'Write-Log Functions' {
        BeforeEach {
            Initialize-Logger -Level "debug"
        }
        
        It 'Should write debug log' {
            { Write-LogDebug "Debug message" } | Should -Not -Throw
        }
        
        It 'Should write info log' {
            { Write-LogInfo "Info message" } | Should -Not -Throw
        }
        
        It 'Should write warning log' {
            { Write-LogWarning "Warning message" } | Should -Not -Throw
        }
        
        It 'Should write error log' {
            { Write-LogError "Error message" } | Should -Not -Throw
        }
        
        It 'Should write success log' {
            { Write-LogSuccess "Success message" } | Should -Not -Throw
        }
    }
    
    Context 'Log Level Filtering' {
        It 'Should not log debug when level is info' {
            $tempDir = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) { $env:TEMP } else { "/tmp" }
            $tempFile = Join-Path $tempDir "test_log_filter_$(Get-Random).txt"
            
            try {
                Initialize-Logger -Level "info" -LogFilePath $tempFile
                
                Write-LogDebug "This should not appear"
                Write-LogInfo "This should appear"
                
                if (Test-Path $tempFile) {
                    $content = Get-Content $tempFile -Raw
                    $content | Should -Not -Match "This should not appear"
                    $content | Should -Match "This should appear"
                }
            } finally {
                # Clean up
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
    }
}

Describe 'ErrorHandler Module' {
    BeforeAll {
        $loggerPath = Join-Path $PSScriptRoot "../../plugins/Common/Logger.psm1"
        Import-Module $loggerPath -Force -Global
        Initialize-Logger -Level "debug"
        
        $modulePath = Join-Path $PSScriptRoot "../../plugins/Common/ErrorHandler.psm1"
        Import-Module $modulePath -Force
    }
    
    AfterAll {
        Remove-Module ErrorHandler -ErrorAction SilentlyContinue
        Remove-Module Logger -ErrorAction SilentlyContinue
    }
    
    Context 'Get-ExitCode' {
        It 'Should return correct exit code for Success' {
            Get-ExitCode -Name "Success" | Should -Be 0
        }
        
        It 'Should return correct exit code for GeneralError' {
            Get-ExitCode -Name "GeneralError" | Should -Be 1
        }
        
        It 'Should return correct exit code for InvalidConfig' {
            Get-ExitCode -Name "InvalidConfig" | Should -Be 2
        }
    }
    
    Context 'Invoke-SafeCommand' {
        It 'Should execute successful command' {
            $result = Invoke-SafeCommand -Command "echo test"
            $result.Success | Should -Be $true
            $result.ExitCode | Should -Be 0
        }
        
        It 'Should handle failed command with ContinueOnError' {
            # Use a command that will fail cross-platform
            $cmd = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) { "cmd /c exit 1" } else { "sh -c 'exit 1'" }
            $result = Invoke-SafeCommand -Command $cmd -ContinueOnError
            $result.Success | Should -Be $false
        }
        
        It 'Should support DryRun mode' {
            $result = Invoke-SafeCommand -Command "echo test" -DryRun
            $result.Success | Should -Be $true
            $result.ExitCode | Should -Be 0
        }
    }
    
    Context 'Test-Prerequisite' {
        It 'Should find existing command' {
            $result = Test-Prerequisite -Name "pwsh" -Type Command
            $result | Should -Be $true
        }
        
        It 'Should detect missing command' {
            $result = Test-Prerequisite -Name "nonexistentcommand12345" -Type Command
            $result | Should -Be $false
        }
    }
    
    Context 'New-ErrorResult' {
        It 'Should create error result object' {
            $result = New-ErrorResult -Message "Test error" -ExitCodeName "GeneralError"
            $result.Success | Should -Be $false
            $result.Message | Should -Be "Test error"
            $result.ExitCode | Should -Be 1
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'New-SuccessResult' {
        It 'Should create success result object' {
            $result = New-SuccessResult -Message "Test success"
            $result.Success | Should -Be $true
            $result.Message | Should -Be "Test success"
            $result.ExitCode | Should -Be 0
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Idempotency Module' {
    BeforeAll {
        $loggerPath = Join-Path $PSScriptRoot "../../plugins/Common/Logger.psm1"
        Import-Module $loggerPath -Force -Global
        Initialize-Logger -Level "debug"
        
        $modulePath = Join-Path $PSScriptRoot "../../plugins/Common/Idempotency.psm1"
        Import-Module $modulePath -Force
        
        $tempDir = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) { $env:TEMP } else { "/tmp" }
        $script:TestStateDir = Join-Path $tempDir "test_state_$(Get-Random)"
    }
    
    AfterAll {
        # Clean up test state directory
        if (Test-Path $TestStateDir) {
            Remove-Item -Path $TestStateDir -Recurse -Force
        }
        Remove-Module Idempotency -ErrorAction SilentlyContinue
        Remove-Module Logger -ErrorAction SilentlyContinue
    }
    
    Context 'Save-State and Get-State' {
        It 'Should save and retrieve state' {
            $stateFile = Join-Path $TestStateDir "test.state.json"
            $state = @{
                Key1 = "Value1"
                Key2 = 42
            }
            
            Save-State -Path $stateFile -State $state
            $retrieved = Get-State -Path $stateFile
            
            $retrieved.Key1 | Should -Be "Value1"
            $retrieved.Key2 | Should -Be 42
            $retrieved.Timestamp | Should -Not -BeNullOrEmpty
        }
        
        It 'Should return null for non-existent state' {
            $stateFile = Join-Path $TestStateDir "nonexistent.state.json"
            $retrieved = Get-State -Path $stateFile
            $retrieved | Should -BeNullOrEmpty
        }
    }
    
    Context 'Test-StateFile' {
        It 'Should detect existing state file' {
            $stateFile = Join-Path $TestStateDir "exists.state.json"
            Save-State -Path $stateFile -State @{ Test = "Data" }
            
            Test-StateFile -Path $stateFile | Should -Be $true
        }
        
        It 'Should detect non-existent state file' {
            $stateFile = Join-Path $TestStateDir "notexists.state.json"
            Test-StateFile -Path $stateFile | Should -Be $false
        }
    }
    
    Context 'Test-ShouldSkipTask' {
        It 'Should not skip if no prior state' {
            $result = Test-ShouldSkipTask -TaskName "TestTask1" -StateDir $TestStateDir
            $result | Should -Be $false
        }
        
        It 'Should skip if completed recently with same inputs' {
            $taskName = "TestTask2"
            $inputs = @{ Param1 = "Value1" }
            
            # Save completion
            Save-TaskCompletion -TaskName $taskName -StateDir $TestStateDir -Inputs $inputs
            
            # Check if should skip
            $result = Test-ShouldSkipTask -TaskName $taskName -StateDir $TestStateDir -CurrentInputs $inputs
            $result | Should -Be $true
        }
        
        It 'Should not skip if inputs changed' {
            $taskName = "TestTask3"
            $oldInputs = @{ Param1 = "Value1" }
            $newInputs = @{ Param1 = "Value2" }
            
            # Save completion with old inputs
            Save-TaskCompletion -TaskName $taskName -StateDir $TestStateDir -Inputs $oldInputs
            
            # Check with new inputs
            $result = Test-ShouldSkipTask -TaskName $taskName -StateDir $TestStateDir -CurrentInputs $newInputs
            $result | Should -Be $false
        }
        
        It 'Should not skip if Force flag is set' {
            $taskName = "TestTask4"
            $inputs = @{ Param1 = "Value1" }
            
            Save-TaskCompletion -TaskName $taskName -StateDir $TestStateDir -Inputs $inputs
            
            $result = Test-ShouldSkipTask -TaskName $taskName -StateDir $TestStateDir -CurrentInputs $inputs -Force
            $result | Should -Be $false
        }
    }
    
    Context 'Save-TaskCompletion' {
        It 'Should save task completion state' {
            $taskName = "CompletionTest"
            $inputs = @{ Input1 = "Test" }
            $outputs = @{ Output1 = "Result" }
            
            { Save-TaskCompletion -TaskName $taskName -StateDir $TestStateDir -Inputs $inputs -Outputs $outputs } | Should -Not -Throw
            
            $stateFile = Join-Path $TestStateDir "$taskName.state.json"
            Test-Path $stateFile | Should -Be $true
        }
    }
}
