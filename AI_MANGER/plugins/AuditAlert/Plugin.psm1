# ModuleName: AuditAlert
param()

function New-4663SubscriptionXml {
  param(
    [Parameter(Mandatory)][string[]]$AllowRoots
  )
  # Build XPath to exclude allowed roots (ObjectName not starting with any allowroot)
  $notClauses = @()
  foreach ($r in $AllowRoots) {
    $rx = $r -replace '\\','\\'
    $notClauses += "not(starts-with(EventData/Data[@Name='ObjectName'], '${rx}'))"
  }
  $notExpr = ($notClauses -join " and ")
  if ([string]::IsNullOrWhiteSpace($notExpr)) { $notExpr = "1=1" }

  $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>
        <![CDATA[
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[(EventID=4663)]]
      and
      *[EventData[${notExpr}]]
    </Select>
  </Query>
</QueryList>
        ]]>
      </Subscription>
      <ValueQueries>
        <Value name="EventRecordID">Event/System/EventRecordID</Value>
      </ValueQueries>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>Queue</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$($env:LOCALAPPDATA)\CLI_AuditAlert\AuditAlert.ps1" -EventRecordId $(EventRecordID)</Arguments>
    </Exec>
  </Actions>
</Task>
"@
  return $xml
}

function Ensure-AuditAlertScript {
  param($Context)
  $dir = Join-Path $env:LOCALAPPDATA "CLI_AuditAlert"
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $dst = Join-Path $dir "AuditAlert.ps1"

  $allow = $Context.Audit.AllowRoots -join '","'
  $toast = $Context.Audit.Notify.Toast
  $jsonl = $Context.Audit.Notify.WriteJson
  $webhook = $Context.Audit.Notify.WebhookUrl

  $body = @"
param(
  [int]`$EventRecordId
)
`$allowRoots = @("${allow}")
`$outFile    = "${jsonl}"
`$useToast   = ${toast}
`$webhookUrl = "${webhook}"

function Get-4663Event([int]`$id) {
  try {
    `$evt = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4663} -MaxEvents 50 |
      Where-Object { `$_.RecordId -eq `$id } | Select-Object -First 1
    return `$evt
  } catch { return `$null }
}

function Parse-Event([System.Diagnostics.Eventing.Reader.EventRecord]`$e) {
  if (-not `$e) { return `$null }
  `$xml = [xml]`$e.ToXml()
  `$h = @{
    TimeCreated   = `$e.TimeCreated
    RecordId      = `$e.RecordId
    MachineName   = `$e.MachineName
    UserId        = (`$e.UserId ? `$e.UserId.Value : "")
    ObjectName    = (`$xml.Event.EventData.Data | Where-Object { `$_.Name -eq "ObjectName" } | Select-Object -First 1).'#text'
    ProcessName   = (`$xml.Event.EventData.Data | Where-Object { `$_.Name -eq "ProcessName" } | Select-Object -First 1).'#text'
    AccessMask    = (`$xml.Event.EventData.Data | Where-Object { `$_.Name -eq "AccessMask" } | Select-Object -First 1).'#text'
    Accesses      = (`$xml.Event.EventData.Data | Where-Object { `$_.Name -eq "Accesses" } | Select-Object -First 1).'#text'
    SubjectUser   = (`$xml.Event.EventData.Data | Where-Object { `$_.Name -eq "SubjectUserName" } | Select-Object -First 1).'#text'
  }
  return `$h
}

`$evt = Get-4663Event -id `$EventRecordId
`$info = Parse-Event `$evt
if (-not `$info) { exit 0 }

# Allow-list filter
foreach (`$r in `$allowRoots) {
  if ([string]::IsNullOrEmpty(`$info.ObjectName)) { break }
  if (`$info.ObjectName.StartsWith(`$r, [System.StringComparison]::OrdinalIgnoreCase)) {
    exit 0
  }
}

# Write JSONL
try {
  `$dir = Split-Path -Parent `$outFile
  if (-not (Test-Path `$dir)) { New-Item -ItemType Directory -Force -Path `$dir | Out-Null }
  (ConvertTo-Json `$info -Compress) + "`n" | Add-Content -Path `$outFile -Encoding UTF8
} catch { }

# Optional toast
if (`$useToast) {
  try {
    if (Get-Module -ListAvailable -Name BurntToast) {
      Import-Module BurntToast
      New-BurntToastNotification -Text "File access outside allow roots", `$info.ObjectName
    }
  } catch { }
}

# Optional webhook (POST)
if (-not [string]::IsNullOrWhiteSpace(`$webhookUrl)) {
  try { Invoke-RestMethod -Method Post -Uri `$webhookUrl -Body (ConvertTo-Json `$info) -ContentType "application/json" } catch { }
}
"@

  Set-Content -Path $dst -Value $body -Encoding UTF8
  return $dst
}

function Register-4663Task {
  param($Context)
  $taskName = $Context.Audit.TaskName
  $xml = New-4663SubscriptionXml -AllowRoots $Context.Audit.AllowRoots
  $tmp = [IO.Path]::GetTempFileName().Replace(".tmp",".xml")
  Set-Content -Path $tmp -Value $xml -Encoding Unicode

  try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
  } catch {}

  try {
    Register-ScheduledTask -TaskName $taskName -Xml (Get-Content $tmp -Raw) -ErrorAction Stop | Out-Null
    return $true
  } catch {
    Write-Warning "Failed to register scheduled task. Try running PowerShell as Administrator."
    return $false
  } finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
  }
}

function Register-Plugin {
  param($Context, $BuildRoot)

  task Audit.InstallAlerts {
    Write-Host "==> Installing 4663 alert task" -ForegroundColor Cyan
    $path = Ensure-AuditAlertScript -Context $Context
    if (Register-4663Task -Context $Context) {
      Write-Host "Scheduled Task installed. Name: $($Context.Audit.TaskName)" -ForegroundColor Green
    }
  }

  task Audit.RemoveAlerts {
    $name = $Context.Audit.TaskName
    try {
      Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop | Out-Null
      Write-Host "Removed task $name" -ForegroundColor Green
    } catch {
      Write-Warning "Failed to remove $name : $_"
    }
  }

  task Audit.TestAlert {
    Write-Host "==> Writing a synthetic alert line (no event required)" -ForegroundColor Cyan
    $dst = $Context.Audit.Notify.WriteJson
    $dir = Split-Path -Parent $dst
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $obj = @{ TimeCreated = Get-Date; RecordId = -1; ObjectName = "$env:TEMP\dummy.txt"; ProcessName="powershell.exe"; SubjectUser=$env:USERNAME }
    (ConvertTo-Json $obj -Compress) + "`n" | Add-Content -Path $dst -Encoding UTF8
    Write-Host "Wrote: $dst" -ForegroundColor Green
  }
}

Export-ModuleMember -Function Register-Plugin
