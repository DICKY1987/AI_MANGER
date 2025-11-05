# Module: Common Interfaces (placeholder for shared helpers)
# Exported helper: Invoke-Quiet
function Invoke-Quiet {
  param([Parameter(Mandatory)][string]$Command)
  try {
    Write-Host "  $Command" -ForegroundColor DarkGray
    $global:LASTEXITCODE = 0
    cmd /c $Command | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "FAILED ($LASTEXITCODE)" }
  } catch {
    Write-Warning $_
  }
}
Export-ModuleMember -Function Invoke-Quiet
