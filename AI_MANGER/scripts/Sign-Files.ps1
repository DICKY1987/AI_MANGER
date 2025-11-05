[CmdletBinding()]
param(
  [string[]]$Paths = @('module/CliStack.psm1','module/CliStack.psd1','scripts/Install-CliStack.ps1'),
  [string]$CertBase64 = $env:CODE_SIGN_CERT_BASE64,
  [string]$CertPassword = $env:CODE_SIGN_CERT_PASSWORD
)
$ErrorActionPreference = 'Stop'
if (-not $CertBase64 -or -not $CertPassword) {
  Write-Host "Code signing certificate not provided; skipping signing."
  exit 0
}
$bytes = [Convert]::FromBase64String($CertBase64)
$tempPfx = Join-Path $env:TEMP 'codesign.pfx'
[IO.File]::WriteAllBytes($tempPfx, $bytes)
$secure = ConvertTo-SecureString $CertPassword -AsPlainText -Force
$cert = Import-PfxCertificate -FilePath $tempPfx -CertStoreLocation cert:\\CurrentUser\\My -Password $secure
foreach ($p in $Paths) {
  if (Test-Path $p) {
    Write-Host "Signing $p"
    Set-AuthenticodeSignature -FilePath $p -Certificate $cert | Out-Null
  } else {
    Write-Host "Skip missing path: $p"
  }
}
# Clean up: remove certificate from store
Remove-Item -Path "cert:\\CurrentUser\\My\\$($cert.Thumbprint)" -ErrorAction SilentlyContinue
Remove-Item $tempPfx -Force -ErrorAction SilentlyContinue
