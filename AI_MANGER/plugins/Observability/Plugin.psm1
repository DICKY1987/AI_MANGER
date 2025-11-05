# ModuleName: Observability
param()

function Rotate-JsonlLog {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [int]$MaxSizeMB = 10,
        [int]$MaxFiles = 5
    )
    
    if (-not (Test-Path $LogPath)) { return }
    
    $file = Get-Item $LogPath
    $sizeMB = [math]::Round($file.Length / 1MB, 2)
    
    if ($sizeMB -ge $MaxSizeMB) {
        $dir = Split-Path -Parent $LogPath
        $name = $file.BaseName
        $ext = $file.Extension
        
        # Rotate existing backup files
        for ($i = $MaxFiles - 1; $i -ge 1; $i--) {
            $src = Join-Path $dir "${name}.${i}${ext}"
            $dst = Join-Path $dir "${name}.$($i + 1)${ext}"
            if (Test-Path $src) {
                if ($i -eq ($MaxFiles - 1)) {
                    Remove-Item $src -Force
                } else {
                    Move-Item $src $dst -Force
                }
            }
        }
        
        # Move current log to .1
        $backup = Join-Path $dir "${name}.1${ext}"
        Move-Item $LogPath $backup -Force
        Write-Host "Rotated $LogPath -> $backup" -ForegroundColor Yellow
        
        # Create new empty log
        New-Item -ItemType File -Path $LogPath -Force | Out-Null
    }
}

function Redact-SensitiveData {
    param(
        [Parameter(Mandatory)][hashtable]$Data
    )
    
    $sensitiveKeys = @(
        'password', 'passwd', 'pwd', 'secret', 'token', 'apikey', 'api_key', 
        'key', 'credential', 'auth', 'bearer', 'authorization', 'webhook',
        'OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'GITHUB_TOKEN'
    )
    
    $redacted = @{}
    foreach ($key in $Data.Keys) {
        $lowerKey = $key.ToLower()
        $isMatch = $false
        
        # Use more efficient matching
        foreach ($pattern in $sensitiveKeys) {
            if ($lowerKey.Contains($pattern.ToLower())) {
                $isMatch = $true
                break
            }
        }
        
        if ($isMatch) {
            $redacted[$key] = '***REDACTED***'
        } elseif ($Data[$key] -is [hashtable]) {
            $redacted[$key] = Redact-SensitiveData -Data $Data[$key]
        } elseif ($Data[$key] -is [array]) {
            $redacted[$key] = $Data[$key] | ForEach-Object {
                if ($_ -is [hashtable]) {
                    Redact-SensitiveData -Data $_
                } else {
                    $_
                }
            }
        } else {
            $redacted[$key] = $Data[$key]
        }
    }
    
    return $redacted
}

function Get-SystemInfo {
    $info = @{
        Hostname = $env:COMPUTERNAME
        Username = $env:USERNAME
        OS = [System.Environment]::OSVersion.VersionString
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Culture = (Get-Culture).Name
        TimeZone = [System.TimeZoneInfo]::Local.Id
        Timestamp = (Get-Date).ToString('o')
    }
    return $info
}

function Get-EnvironmentSnapshot {
    $envVars = @{}
    Get-ChildItem Env: | ForEach-Object {
        $envVars[$_.Name] = $_.Value
    }
    return $envVars
}

function Collect-DiagnosticsBundle {
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [hashtable]$Context,
        [string]$BuildRoot
    )
    
    Write-Host "==> Collecting diagnostics bundle" -ForegroundColor Cyan
    
    $bundle = @{
        Meta = @{
            Collected = (Get-Date).ToString('o')
            Version = '1.0.0'
        }
        System = Get-SystemInfo
        Environment = Get-EnvironmentSnapshot
        Health = @{}
        Config = @{}
        Logs = @{}
        Audit = @{}
    }
    
    # Collect health check data if available
    $healthFile = $Context.Reports.Dir
    if ($healthFile) {
        $healthPath = [Environment]::ExpandEnvironmentVariables($healthFile)
        $healthJson = Join-Path $healthPath "health.json"
        if (Test-Path $healthJson) {
            try {
                $bundle.Health = Get-Content $healthJson -Raw | ConvertFrom-Json -AsHashtable
            } catch {
                $bundle.Health = @{ error = "Failed to read health.json" }
            }
        }
    }
    
    # Collect config (redacted)
    if ($BuildRoot) {
        $configPath = Join-Path $BuildRoot "config\toolstack.config.json"
        if (Test-Path $configPath) {
            try {
                $configData = Get-Content $configPath -Raw | ConvertFrom-Json -AsHashtable
                $bundle.Config = Redact-SensitiveData -Data $configData
            } catch {
                $bundle.Config = @{ error = "Failed to read config" }
            }
        }
    }
    
    # Collect audit logs (last 100 lines)
    if ($Context.Audit -and $Context.Audit.Notify.WriteJson) {
        $auditPath = [Environment]::ExpandEnvironmentVariables($Context.Audit.Notify.WriteJson)
        if (Test-Path $auditPath) {
            try {
                $lines = Get-Content $auditPath -Tail 100 -ErrorAction SilentlyContinue
                $bundle.Audit = @{
                    LastEntries = $lines.Count
                    Sample = ($lines | Select-Object -First 5)
                }
            } catch {
                $bundle.Audit = @{ error = "Failed to read audit log" }
            }
        }
    }
    
    # Redact the entire bundle
    $redactedBundle = Redact-SensitiveData -Data $bundle
    
    # Ensure output directory exists
    $outDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }
    
    # Write bundle
    $json = ConvertTo-Json $redactedBundle -Depth 10
    Set-Content -Path $OutputPath -Value $json -Encoding UTF8
    
    Write-Host "Diagnostics bundle written to: $OutputPath" -ForegroundColor Green
    Write-Host "Bundle size: $([math]::Round((Get-Item $OutputPath).Length / 1KB, 2)) KB" -ForegroundColor Gray
    
    return $OutputPath
}

function Register-PeriodicHealthScan {
    param(
        [string]$TaskName = "CLI_HealthScan",
        [string]$ScriptPath,
        [int]$IntervalMinutes = 60
    )
    
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
    
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
        -RepetitionDuration ([TimeSpan]::MaxValue)
    
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME `
        -LogonType Interactive -RunLevel Limited
    
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances Queue `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)
    
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    } catch {}
    
    try {
        Register-ScheduledTask -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Warning "Failed to register scheduled task: $_"
        return $false
    }
}

function Register-Plugin {
    param($Context, $BuildRoot)
    
    function Expand-Env([string]$s) { [Environment]::ExpandEnvironmentVariables($s) }
    
    task Observability.RotateLogs {
        Write-Host "==> Rotating JSONL logs" -ForegroundColor Cyan
        
        $logsToRotate = @()
        
        # Add audit log if configured
        if ($Context.Audit -and $Context.Audit.Notify.WriteJson) {
            $logsToRotate += @{
                Path = Expand-Env $Context.Audit.Notify.WriteJson
                MaxSizeMB = 10
                MaxFiles = 5
            }
        }
        
        # Add observability logs if configured
        if ($Context.Observability -and $Context.Observability.LogFiles) {
            foreach ($log in $Context.Observability.LogFiles) {
                $logsToRotate += @{
                    Path = Expand-Env $log.Path
                    MaxSizeMB = $log.MaxSizeMB ?? 10
                    MaxFiles = $log.MaxFiles ?? 5
                }
            }
        }
        
        foreach ($logConfig in $logsToRotate) {
            if (Test-Path $logConfig.Path) {
                Rotate-JsonlLog -LogPath $logConfig.Path `
                    -MaxSizeMB $logConfig.MaxSizeMB `
                    -MaxFiles $logConfig.MaxFiles
            } else {
                Write-Host "Log file not found: $($logConfig.Path)" -ForegroundColor Gray
            }
        }
        
        Write-Host "Log rotation complete" -ForegroundColor Green
    }
    
    task Observability.Diagnostics {
        Write-Host "==> Generating diagnostics bundle" -ForegroundColor Cyan
        
        $reportsDir = Expand-Env $Context.Reports.Dir
        if (-not (Test-Path $reportsDir)) {
            New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null
        }
        
        $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $bundlePath = Join-Path $reportsDir "diagnostics-$timestamp.json"
        
        Collect-DiagnosticsBundle -OutputPath $bundlePath -Context $Context -BuildRoot $BuildRoot
    }
    
    task Observability.InstallHealthScan {
        Write-Host "==> Installing periodic health scan" -ForegroundColor Cyan
        
        # Create health scan script
        $scriptDir = Join-Path $env:LOCALAPPDATA "CLI_HealthScan"
        if (-not (Test-Path $scriptDir)) {
            New-Item -ItemType Directory -Force -Path $scriptDir | Out-Null
        }
        
        $scriptPath = Join-Path $scriptDir "HealthScan.ps1"
        $configPath = Join-Path $BuildRoot "config\toolstack.config.json"
        
        $scriptContent = @"
# Periodic health scan script
`$ErrorActionPreference = 'SilentlyContinue'
Set-Location '$BuildRoot'
Import-Module InvokeBuild -ErrorAction SilentlyContinue
if (Get-Module InvokeBuild) {
    Invoke-Build Health.Check -File '$BuildRoot\build.ps1'
}
"@
        
        Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8
        
        $intervalMin = 60
        if ($Context.Observability -and $Context.Observability.HealthScanIntervalMinutes) {
            $intervalMin = $Context.Observability.HealthScanIntervalMinutes
        }
        
        if (Register-PeriodicHealthScan -ScriptPath $scriptPath -IntervalMinutes $intervalMin) {
            Write-Host "Periodic health scan installed (interval: $intervalMin minutes)" -ForegroundColor Green
        }
    }
    
    task Observability.RemoveHealthScan {
        Write-Host "==> Removing periodic health scan" -ForegroundColor Cyan
        try {
            Unregister-ScheduledTask -TaskName "CLI_HealthScan" -Confirm:$false -ErrorAction Stop
            Write-Host "Periodic health scan removed" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to remove health scan task: $_"
        }
    }
    
    task Observability.Telemetry {
        Write-Host "==> Telemetry hook (placeholder)" -ForegroundColor Cyan
        Write-Host "Future: Send anonymized usage/health metrics to telemetry endpoint" -ForegroundColor Gray
        
        if ($Context.Observability -and $Context.Observability.TelemetryUrl) {
            Write-Host "Telemetry endpoint: $($Context.Observability.TelemetryUrl)" -ForegroundColor Gray
        } else {
            Write-Host "No telemetry endpoint configured" -ForegroundColor Gray
        }
    }
}

Export-ModuleMember -Function Register-Plugin
