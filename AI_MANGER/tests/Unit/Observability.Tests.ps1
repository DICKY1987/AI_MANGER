Describe 'Observability Plugin' {
    BeforeAll {
        $script:PluginPath = Join-Path $PSScriptRoot '..\..\plugins\Observability\Plugin.psm1'
        Import-Module $script:PluginPath -Force
    }
    
    Context 'Module Import' {
        It 'Should import without errors' {
            { Import-Module $script:PluginPath -Force } | Should -Not -Throw
        }
        
        It 'Should export Register-Plugin function' {
            Get-Command -Module Observability -Name Register-Plugin -ErrorAction SilentlyContinue | 
                Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'Redact-SensitiveData' {
        BeforeAll {
            Import-Module $script:PluginPath -Force -ArgumentList @()
            # Get internal function using reflection
            $module = Get-Module Observability
            $script:RedactFunc = & $module { ${function:Redact-SensitiveData} }
        }
        
        It 'Should redact password fields' {
            $data = @{ password = 'secret123'; username = 'user' }
            $redacted = & $script:RedactFunc -Data $data
            $redacted.password | Should -Be '***REDACTED***'
            $redacted.username | Should -Be 'user'
        }
        
        It 'Should redact API key fields' {
            $data = @{ OPENAI_API_KEY = 'sk-1234567890'; setting = 'value' }
            $redacted = & $script:RedactFunc -Data $data
            $redacted.OPENAI_API_KEY | Should -Be '***REDACTED***'
            $redacted.setting | Should -Be 'value'
        }
        
        It 'Should redact nested sensitive data' {
            $data = @{
                config = @{
                    api_token = 'token123'
                    safe_value = 'public'
                }
                other = 'data'
            }
            $redacted = & $script:RedactFunc -Data $data
            $redacted.config.api_token | Should -Be '***REDACTED***'
            $redacted.config.safe_value | Should -Be 'public'
            $redacted.other | Should -Be 'data'
        }
        
        It 'Should handle empty data' {
            $data = @{}
            $redacted = & $script:RedactFunc -Data $data
            $redacted | Should -Not -BeNullOrEmpty
            $redacted.Count | Should -Be 0
        }
    }
    
    Context 'Rotate-JsonlLog' {
        BeforeAll {
            $script:TestDir = Join-Path $TestDrive 'logs'
            New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
            Import-Module $script:PluginPath -Force -ArgumentList @()
            $module = Get-Module Observability
            $script:RotateFunc = & $module { ${function:Rotate-JsonlLog} }
        }
        
        It 'Should not rotate small log files' {
            $logPath = Join-Path $script:TestDir 'test.jsonl'
            'small log' | Set-Content $logPath
            
            & $script:RotateFunc -LogPath $logPath -MaxSizeMB 10 -MaxFiles 5
            
            Test-Path $logPath | Should -Be $true
            Test-Path (Join-Path $script:TestDir 'test.1.jsonl') | Should -Be $false
        }
        
        It 'Should create backup when log exceeds max size' {
            $logPath = Join-Path $script:TestDir 'large.jsonl'
            
            # Create a file larger than 1MB
            $content = 'x' * (1MB + 1KB)
            $content | Set-Content $logPath -NoNewline
            
            & $script:RotateFunc -LogPath $logPath -MaxSizeMB 1 -MaxFiles 5
            
            Test-Path (Join-Path $script:TestDir 'large.1.jsonl') | Should -Be $true
            (Get-Item $logPath).Length | Should -BeLessThan 1KB
        }
        
        It 'Should handle non-existent log file gracefully' {
            $logPath = Join-Path $script:TestDir 'nonexistent.jsonl'
            { & $script:RotateFunc -LogPath $logPath -MaxSizeMB 10 -MaxFiles 5 } | Should -Not -Throw
        }
    }
    
    Context 'Get-SystemInfo' {
        BeforeAll {
            Import-Module $script:PluginPath -Force -ArgumentList @()
            $module = Get-Module Observability
            $script:SystemInfoFunc = & $module { ${function:Get-SystemInfo} }
        }
        
        It 'Should return system information' {
            $info = & $script:SystemInfoFunc
            $info | Should -Not -BeNullOrEmpty
            $info.Keys | Should -Contain 'Hostname'
            $info.Keys | Should -Contain 'Username'
            $info.Keys | Should -Contain 'OS'
            $info.Keys | Should -Contain 'PowerShellVersion'
            $info.Keys | Should -Contain 'Timestamp'
        }
        
        It 'Should include valid timestamp' {
            $info = & $script:SystemInfoFunc
            { [DateTime]::Parse($info.Timestamp) } | Should -Not -Throw
        }
    }
    
    Context 'Collect-DiagnosticsBundle' {
        BeforeAll {
            $script:TestDir = Join-Path $TestDrive 'diagnostics'
            New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
            Import-Module $script:PluginPath -Force -ArgumentList @()
            $module = Get-Module Observability
            $script:CollectFunc = & $module { ${function:Collect-DiagnosticsBundle} }
        }
        
        It 'Should create diagnostics bundle file' {
            $outputPath = Join-Path $script:TestDir 'bundle.json'
            $context = @{
                Reports = @{ Dir = $script:TestDir }
                Audit = @{ Notify = @{ WriteJson = '' } }
            }
            
            & $script:CollectFunc -OutputPath $outputPath -Context $context
            
            Test-Path $outputPath | Should -Be $true
        }
        
        It 'Should include required sections in bundle' {
            $outputPath = Join-Path $script:TestDir 'bundle2.json'
            $context = @{
                Reports = @{ Dir = $script:TestDir }
                Audit = @{ Notify = @{ WriteJson = '' } }
            }
            
            & $script:CollectFunc -OutputPath $outputPath -Context $context
            
            $bundle = Get-Content $outputPath -Raw | ConvertFrom-Json -AsHashtable
            $bundle.Keys | Should -Contain 'Meta'
            $bundle.Keys | Should -Contain 'System'
            $bundle.Keys | Should -Contain 'Environment'
            $bundle.Keys | Should -Contain 'Health'
            $bundle.Keys | Should -Contain 'Config'
        }
    }
    
    AfterAll {
        Remove-Module Observability -Force -ErrorAction SilentlyContinue
    }
}
