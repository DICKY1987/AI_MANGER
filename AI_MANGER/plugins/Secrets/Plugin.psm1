# ModuleName: Secrets (DPAPI user-protected vault)
param()

function Register-Plugin {
  param($Context, $BuildRoot)

  function Expand-Env([string]$s) { [Environment]::ExpandEnvironmentVariables($s) }
  function Ensure-VaultPath([string]$p) {
    $full = Expand-Env $p
    $dir = Split-Path -Parent $full
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (-not (Test-Path $full)) { '{}' | Set-Content -Path $full -Encoding UTF8 }
    return $full
  }
  function Load-Vault() {
    $path = Ensure-VaultPath $Context.Secrets.VaultPath
    $json = Get-Content -Path $path -Raw -Encoding UTF8
    return ($json | ConvertFrom-Json)
  }
  function Save-Vault($obj) {
    $path = Expand-Env $Context.Secrets.VaultPath
    ($obj | ConvertTo-Json -Depth 4) | Set-Content -Path $path -Encoding UTF8
    Write-Host "Saved vault: $path" -ForegroundColor Green
  }
  function Protect-String([string]$s) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($s)
    $enc = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [Convert]::ToBase64String($enc)
  }
  function Unprotect-String([string]$b64) {
    try {
      $enc = [Convert]::FromBase64String($b64)
      $bytes = [Security.Cryptography.ProtectedData]::Unprotect($enc, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
      return [Text.Encoding]::UTF8.GetString($bytes)
    } catch { return $null }
  }

  task Secrets.List {
    $v = Load-Vault
    ($v.PSObject.Properties.Name | Sort-Object) | ForEach-Object { $_ } | Out-Host
  }

  task Secrets.Set {
    param([string]$Name)
    if (-not $Name) { $Name = Read-Host "Secret name" }
    $raw = Read-Host "Secret value (input hidden)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($raw)
    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $v = Load-Vault
    $v | Add-Member -NotePropertyName $Name -NotePropertyValue (Protect-String $plain) -Force
    Save-Vault $v
  }

  task Secrets.Get {
    param([string]$Name)
    if (-not $Name) { $Name = Read-Host "Secret name" }
    $v = Load-Vault
    if (-not $v.PSObject.Properties.Name -contains $Name) { Write-Warning "Not found: $Name"; return }
    $plain = Unprotect-String $v.$Name
    # Do NOT print by default; set to clipboard
    if ($plain) {
      Set-Clipboard -Value $plain
      Write-Host "Secret copied to clipboard." -ForegroundColor Green
    } else {
      Write-Warning "Failed to decrypt."
    }
  }

  task Secrets.ExportEnv {
    # Export mapped env vars for this session
    $v = Load-Vault
    foreach ($pair in $Context.Secrets.EnvMap.GetEnumerator()) {
      $envName = $pair.Key
      $secretName = $pair.Value
      if ($v.PSObject.Properties.Name -contains $secretName) {
        $val = Unprotect-String $v.$secretName
        if ($val) {
          $env:$envName = $val
          Write-Host "Set $envName" -ForegroundColor Green
        }
      }
    }
  }
}
Export-ModuleMember -Function Register-Plugin
