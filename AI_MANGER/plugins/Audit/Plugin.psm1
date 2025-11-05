# ModuleName: Audit
param()
function Register-Plugin {
  param($Context, $BuildRoot)

  task AuditSetup {
    Write-Host "==> Audit setup (manual/assisted)" -ForegroundColor Cyan
    Write-Host "Enable: Local Security Policy -> Audit Object Access (Success+Failure)"
    Write-Host "Folder Auditing: Add 'Everyone' -> All -> Applies to 'This folder, subfolders and files' for Delete+Write"
    Write-Host "Optional: Create a Scheduled Task to watch Event ID 4663 and alert."
    Write-Host "Tip: Restrict ACLs on $($Context.ToolsRoot) subfolders to you + Administrators."
  }
}
Export-ModuleMember -Function Register-Plugin
