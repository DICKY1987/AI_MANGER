# InvokeBuild Modular Stack (Centralized CLI + Guards)

## Prereqs
```powershell
# PowerShell 7 recommended
Install-Module InvokeBuild -Scope CurrentUser -Force
```

## Run
```powershell
# From repo root:
Invoke-Build -File .\build.ps1           # runs default task: Rebuild
Invoke-Build -File .\build.ps1 Bootstrap  # just env + installs
Invoke-Build -File .\build.ps1 Verify     # check versions
Invoke-Build -File .\build.ps1 WatcherWatch  # start real-time watcher
```

## Customize
- Edit `config\toolstack.config.json` for paths and package lists.
- Add plugins in `plugins\<Name>\Plugin.psm1`; implement `Register-Plugin` and call `task ... {}`.
- Helper scripts live in `scripts\` (already included).


## New plugins & tasks

### Pinning
```powershell
Invoke-Build -File .\build.ps1 Pin.Report   # show current vs desired versions
Invoke-Build -File .\build.ps1 Pin.Sync     # enforce exact versions from config.Pins
```

### AuditAlert (Event 4663)
```powershell
Invoke-Build -File .\build.ps1 Audit.InstallAlerts  # register scheduled task (may need admin)
Invoke-Build -File .\build.ps1 Audit.RemoveAlerts   # remove the task
Invoke-Build -File .\build.ps1 Audit.TestAlert      # write a synthetic line to JSONL
```

### MasterBin (single PATH wrappers)
- Enable in `config\toolstack.config.json` → `MasterBin.Enable: true`
```powershell
Invoke-Build -File .\build.ps1 MasterBin.Rebuild
Invoke-Build -File .\build.ps1 MasterBin.Clean
```


### Update
Check & update global CLIs.
```powershell
Invoke-Build -File .\build.ps1 Update.Check   # writes updates.json
Invoke-Build -File .\build.ps1 Update.All     # npm update -g + pipx upgrade --all
```

### Scanner
Find duplicate files by hash and misplaced cache/config dirs.
```powershell
Invoke-Build -File .\build.ps1 Scan.Report    # writes duplicates.json + misplaced.json
```

### Secrets (DPAPI User Vault)
Store and export API keys/tokens securely (tied to your Windows user).
```powershell
Invoke-Build -File .\build.ps1 Secrets.Set          # prompt
Invoke-Build -File .\build.ps1 Secrets.List
Invoke-Build -File .\build.ps1 Secrets.Get -Name OPENAI   # copies to clipboard
Invoke-Build -File .\build.ps1 Secrets.ExportEnv     # sets env for this session
```

### HealthCheck
Quick environment sanity check -> JSON report.
```powershell
Invoke-Build -File .\build.ps1 Health.Check   # writes health.json
```
