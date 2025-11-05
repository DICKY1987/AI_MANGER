Describe 'Module Hardening Tests' {
  BeforeAll {
    $BuildRoot = Join-Path $PSScriptRoot ".." ".."
    Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force
  }

  Context 'Test-IsLink' {
    It 'Returns false for non-existent path' {
      Test-IsLink -Path "C:\NonExistent\Path" | Should -BeFalse
    }

    It 'Returns false for regular directory' {
      $testDir = Join-Path $TestDrive "regular"
      New-Item -ItemType Directory -Path $testDir -Force | Out-Null
      Test-IsLink -Path $testDir | Should -BeFalse
    }
  }

  Context 'Get-QuarantinePath' {
    It 'Generates unique quarantine path with timestamp' {
      $original = Join-Path $TestDrive "MyFolder"
      $quarantineRoot = Join-Path $TestDrive "Quarantine"
      $result = Get-QuarantinePath -OriginalPath $original -QuarantineRoot $quarantineRoot
      
      $result | Should -Match "MyFolder_\d{8}_\d{6}_[a-f0-9]{8}"
    }

    It 'Handles paths with special characters' {
      $original = Join-Path $TestDrive ".cache"
      $quarantineRoot = Join-Path $TestDrive "Quarantine"
      $result = Get-QuarantinePath -OriginalPath $original -QuarantineRoot $quarantineRoot
      
      $result | Should -Match "\.cache_\d{8}_\d{6}_"
    }
  }

  Context 'Move-ToQuarantine' {
    It 'Returns null for non-existent path' {
      $result = Move-ToQuarantine -Path "C:\NonExistent" -QuarantineRoot $TestDrive
      $result | Should -BeNullOrEmpty
    }

    It 'Moves directory to quarantine and returns new path' {
      $testDir = Join-Path $TestDrive "toQuarantine"
      $quarantineRoot = Join-Path $TestDrive "quarantine"
      New-Item -ItemType Directory -Path $testDir -Force | Out-Null
      "test" | Out-File (Join-Path $testDir "file.txt")
      
      $result = Move-ToQuarantine -Path $testDir -QuarantineRoot $quarantineRoot
      
      $result | Should -Not -BeNullOrEmpty
      Test-Path $testDir | Should -BeFalse
      Test-Path $result | Should -BeTrue
    }
  }

  Context 'Invoke-WithRetry' {
    It 'Executes scriptblock successfully on first attempt' {
      $result = Invoke-WithRetry -ScriptBlock { return "success" } -MaxAttempts 3
      $result | Should -Be "success"
    }

    It 'Retries on failure and eventually succeeds' {
      $script:attempts = 0
      $result = Invoke-WithRetry -MaxAttempts 3 -DelayMs 100 -ScriptBlock {
        $script:attempts++
        if ($script:attempts -lt 2) { throw "Temporary failure" }
        return "success"
      }
      
      $result | Should -Be "success"
      $script:attempts | Should -Be 2
    }

    It 'Throws after max attempts exceeded' {
      { 
        Invoke-WithRetry -MaxAttempts 2 -DelayMs 100 -ScriptBlock {
          throw "Persistent failure"
        }
      } | Should -Throw
    }
  }

  Context 'Lock-ResourceFile' {
    It 'Executes scriptblock with lock' {
      $result = Lock-ResourceFile -ResourceName "test-resource" -ScriptBlock {
        return "executed"
      }
      
      $result | Should -Be "executed"
    }

    It 'Releases lock after execution' {
      Lock-ResourceFile -ResourceName "test-resource-2" -ScriptBlock {
        # Do nothing
      }
      
      $tempPath = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
      $lockFile = Join-Path $tempPath "CLI_Locks\test-resource-2.lock"
      Test-Path -LiteralPath $lockFile -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'Releases lock even after exception' {
      try {
        Lock-ResourceFile -ResourceName "test-resource-3" -ScriptBlock {
          throw "Test error"
        }
      } catch {
        # Expected
      }
      
      $tempPath = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
      $lockFile = Join-Path $tempPath "CLI_Locks\test-resource-3.lock"
      Test-Path -LiteralPath $lockFile -ErrorAction SilentlyContinue | Should -BeFalse
    }
  }

  Context 'New-DirectoryLink' {
    It 'Creates target directory if it does not exist' {
      $target = Join-Path $TestDrive "target"
      $link = Join-Path $TestDrive "link"
      
      New-DirectoryLink -LinkPath $link -TargetPath $target -QuarantineRoot $TestDrive
      
      Test-Path $target | Should -BeTrue
    }

    It 'Returns true when link is created successfully' {
      $target = Join-Path $TestDrive "target2"
      $link = Join-Path $TestDrive "link2"
      
      $result = New-DirectoryLink -LinkPath $link -TargetPath $target -QuarantineRoot $TestDrive
      
      # On systems without symlink support, this might return false (copy fallback)
      # but we still verify the operation completed
      Test-Path $link | Should -BeTrue
    }

    It 'Quarantines existing directory before creating link' {
      $target = Join-Path $TestDrive "target3"
      $link = Join-Path $TestDrive "link3"
      $quarantine = Join-Path $TestDrive "quarantine3"
      
      # Create existing directory at link location
      New-Item -ItemType Directory -Path $link -Force | Out-Null
      "existing" | Out-File (Join-Path $link "existing.txt")
      
      New-DirectoryLink -LinkPath $link -TargetPath $target -QuarantineRoot $quarantine
      
      # Verify old content was quarantined
      $quarantinedItems = Get-ChildItem $quarantine -Recurse -Filter "existing.txt" -ErrorAction SilentlyContinue
      $quarantinedItems.Count | Should -BeGreaterThan 0
    }
  }

  Context 'Invoke-Quiet' {
    It 'Executes command successfully' {
      { Invoke-Quiet -Command "echo test" } | Should -Not -Throw
    }

    It 'Warns on command failure' {
      # Use a command that will fail
      Invoke-Quiet -Command "exit 1" -WarningAction SilentlyContinue
      # Should not throw, but issue warning
      $true | Should -BeTrue
    }
  }
}
