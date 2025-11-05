# ModuleName: Secrets (DPAPI user-protected vault)
param()

function Register-Plugin {
  param($Context, $BuildRoot)
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  function Expand-Env([string]$s) { [Environment]::ExpandEnvironmentVariables($s) }
  function Ensure-VaultPath([string]$p) {
    try {
      $full = Expand-Env $p
      $dir = Split-Path -Parent $full
      if (-not (Test-Path $dir)) { 
        New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null 
      }
      if (-not (Test-Path $full)) { 
        '{}' | Set-Content -Path $full -Encoding UTF8 -ErrorAction Stop
      }
      return $full
    } catch {
      Write-Warning "Failed to ensure vault path ${p}: $_"
      throw
    }
  }
  function Load-Vault() {
    try {
      $path = Ensure-VaultPath $Context.Secrets.VaultPath
      Lock-ResourceFile -ResourceName "Secrets.Vault" -ScriptBlock {
        $json = Get-Content -Path $path -Raw -Encoding UTF8 -ErrorAction Stop
        return ($json | ConvertFrom-Json -ErrorAction Stop)
      }
    } catch {
      Write-Warning "Failed to load vault: $_"
      throw
    }
  }
  function Save-Vault($obj) {
    try {
      $path = Expand-Env $Context.Secrets.VaultPath
      Lock-ResourceFile -ResourceName "Secrets.Vault" -ScriptBlock {
        ($obj | ConvertTo-Json -Depth 4) | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop
        Write-Host "Saved vault: $path" -ForegroundColor Green
      }
    } catch {
      Write-Warning "Failed to save vault: $_"
      throw
    }
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
    try {
      if (-not $Name) { $Name = Read-Host "Secret name" }
      if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Warning "Secret name cannot be empty"
        return
      }
      
      $raw = Read-Host "Secret value (input hidden)" -AsSecureString
      $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($raw)
      try { 
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) 
      } finally { 
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) 
      }
      
      if ([string]::IsNullOrWhiteSpace($plain)) {
        Write-Warning "Secret value cannot be empty"
        return
      }
      
      $v = Load-Vault
      $v | Add-Member -NotePropertyName $Name -NotePropertyValue (Protect-String $plain) -Force
      Save-Vault $v
      Write-Host "Secret '$Name' saved successfully" -ForegroundColor Green
    } catch {
      Write-Warning "Failed to set secret: $_"
    }
  }

  task Secrets.Get {
    param([string]$Name)
    try {
      if (-not $Name) { $Name = Read-Host "Secret name" }
      if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Warning "Secret name cannot be empty"
        return
      }
      
      $v = Load-Vault
      if (-not $v.PSObject.Properties.Name -contains $Name) { 
        Write-Warning "Not found: $Name"
        return 
      }
      
      $plain = Unprotect-String $v.$Name
      # Do NOT print by default; set to clipboard
      if ($plain) {
        Set-Clipboard -Value $plain
        Write-Host "Secret copied to clipboard." -ForegroundColor Green
      } else {
        Write-Warning "Failed to decrypt secret '$Name'"
      }
    } catch {
      Write-Warning "Failed to get secret: $_"
    }
  }

  task Secrets.ExportEnv {
    try {
      # Export mapped env vars for this session
      $v = Load-Vault
      $exported = 0
      
      foreach ($pair in $Context.Secrets.EnvMap.GetEnumerator()) {
        $envName = $pair.Key
        $secretName = $pair.Value
        if ($v.PSObject.Properties.Name -contains $secretName) {
          $val = Unprotect-String $v.$secretName
          if ($val) {
            $env:$envName = $val
            Write-Host "Set $envName" -ForegroundColor Green
            $exported++
          } else {
            Write-Warning "Failed to decrypt secret '$secretName' for env var '$envName'"
          }
        } else {
          Write-Verbose "Secret '$secretName' not found in vault for env var '$envName'"
        }
      }
      
      Write-Host "Exported $exported environment variables" -ForegroundColor Green
    } catch {
      Write-Warning "Failed to export environment variables: $_"
    }
  }
}
Export-ModuleMember -Function Register-Plugin
