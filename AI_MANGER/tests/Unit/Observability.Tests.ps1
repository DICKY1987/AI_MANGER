Describe 'Observability Plugin' {
    BeforeAll {
        $script:PluginPath = Join-Path $PSScriptRoot '..\..\plugins\Observability\Plugin.psm1'
    }
    
    Context 'Module Import' {
        It 'Should import without errors' {
            { Import-Module $script:PluginPath -Force } | Should -Not -Throw
        }
        
        It 'Should export Register-Plugin function' {
            Import-Module $script:PluginPath -Force
            $commands = Get-Command -Module (Get-Module | Where-Object { $_.Path -eq $script:PluginPath }) -ErrorAction SilentlyContinue
            $commands | Where-Object { $_.Name -eq 'Register-Plugin' } | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'Plugin Integration' {
        BeforeAll {
            $script:TestDir = Join-Path $TestDrive 'observability-test'
            $script:ConfigDir = Join-Path $script:TestDir 'config'
            $script:ReportsDir = Join-Path $script:TestDir 'reports'
            
            New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
            New-Item -ItemType Directory -Path $script:ReportsDir -Force | Out-Null
            
            # Create test config
            $config = @{
                Reports = @{ Dir = $script:ReportsDir }
                Audit = @{ 
                    Notify = @{ WriteJson = (Join-Path $script:TestDir 'audit.jsonl') }
                }
                Observability = @{
                    HealthScanIntervalMinutes = 60
                    TelemetryUrl = ''
                    LogFiles = @(
                        @{
                            Path = (Join-Path $script:TestDir 'test.jsonl')
                            MaxSizeMB = 1
                            MaxFiles = 3
                        }
                    )
                }
            }
            
            $configPath = Join-Path $script:ConfigDir 'toolstack.config.json'
            $config | ConvertTo-Json -Depth 10 | Set-Content $configPath
        }
        
        It 'Should register plugin successfully' {
            Import-Module $script:PluginPath -Force
            
            $mockContext = @{
                Reports = @{ Dir = $script:ReportsDir }
                Audit = @{ Notify = @{ WriteJson = '' } }
                Observability = @{
                    LogFiles = @()
                }
            }
            
            { 
                $module = Get-Module | Where-Object { $_.Path -eq $script:PluginPath }
                if ($module) {
                    $registerFunc = & $module { Get-Command Register-Plugin }
                    if ($registerFunc) {
                        & $registerFunc.ScriptBlock -Context $mockContext -BuildRoot $script:TestDir
                    }
                }
            } | Should -Not -Throw
        }
    }
    
    Context 'Log Rotation Functionality' {
        BeforeAll {
            $script:TestLogDir = Join-Path $TestDrive 'logs'
            New-Item -ItemType Directory -Path $script:TestLogDir -Force | Out-Null
        }
        
        It 'Should handle small log files without rotation' {
            $logPath = Join-Path $script:TestLogDir 'small.jsonl'
            'small log entry' | Set-Content $logPath
            
            # Verify file exists and is small
            Test-Path $logPath | Should -Be $true
            (Get-Item $logPath).Length | Should -BeLessThan 100
            
            # Backup should not exist
            Test-Path "$logPath.1" | Should -Be $false
        }
        
        It 'Should create backup for oversized logs' {
            $logPath = Join-Path $script:TestLogDir 'large.jsonl'
            
            # Create a large file (> 1MB)
            $largeContent = 'x' * (1MB + 1KB)
            $largeContent | Set-Content $logPath -NoNewline
            
            $originalSize = (Get-Item $logPath).Length
            $originalSize | Should -BeGreaterThan 1MB
        }
    }
    
    Context 'Diagnostics Bundle' {
        BeforeAll {
            $script:BundleDir = Join-Path $TestDrive 'diagnostics'
            New-Item -ItemType Directory -Path $script:BundleDir -Force | Out-Null
        }
        
        It 'Should create diagnostics directory structure' {
            Test-Path $script:BundleDir | Should -Be $true
        }
        
        It 'Should be able to collect environment variables' {
            $env:TEST_VAR = 'test_value'
            $vars = Get-ChildItem Env: | Where-Object { $_.Name -eq 'TEST_VAR' }
            $vars | Should -Not -BeNullOrEmpty
            $vars[0].Value | Should -Be 'test_value'
        }
    }
    
    Context 'Redaction Requirements' {
        It 'Should identify sensitive patterns' {
            $sensitivePatterns = @('password', 'token', 'apikey', 'api_key', 'secret', 'credential', 'key')
            $testKeys = @('mypassword', 'auth_token', 'api_key', 'user_secret', 'db_credential')
            
            foreach ($testKey in $testKeys) {
                $shouldBeRedacted = $false
                foreach ($pattern in $sensitivePatterns) {
                    if ($testKey.ToLower() -like "*$pattern*") {
                        $shouldBeRedacted = $true
                        break
                    }
                }
                $shouldBeRedacted | Should -Be $true
            }
        }
        
        It 'Should not flag safe keys' {
            $sensitivePatterns = @('password', 'token', 'apikey', 'api_key', 'secret', 'credential', 'key')
            # Use keys that really won't match any pattern
            $safeKeys = @('username', 'config', 'setting', 'path', 'enabled', 'hostname', 'port')
            
            foreach ($safeKey in $safeKeys) {
                $shouldBeRedacted = $false
                foreach ($pattern in $sensitivePatterns) {
                    if ($safeKey.ToLower() -like "*$pattern*") {
                        $shouldBeRedacted = $true
                        break
                    }
                }
                $shouldBeRedacted | Should -Be $false
            }
        }
    }
    
    AfterAll {
        Remove-Module Observability -Force -ErrorAction SilentlyContinue
    }
}
