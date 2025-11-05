# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

**AI_MANGER** is a modular InvokeBuild-based CLI management system for Windows that centralizes and enforces standardized configurations for development tools (Python/Node.js CLIs). It provides a plugin architecture for managing npm/pipx packages, version pinning, configuration centralization, security auditing, and environment health checks.

## Prerequisites

```powershell
# PowerShell 7+ (required)
winget install Microsoft.PowerShell

# InvokeBuild module
Install-Module InvokeBuild -Scope CurrentUser -Force
```

## Build System Commands

All commands run from the repository root:

```powershell
# Default task: runs complete rebuild (Bootstrap + WatcherEnforce + AuditSetup)
Invoke-Build -File .\build.ps1

# Bootstrap environment: install pipx/npm packages, apply config centralization
Invoke-Build -File .\build.ps1 Bootstrap

# Verify all tools are installed and working
Invoke-Build -File .\build.ps1 Verify

# Start real-time filesystem watcher for cache/config enforcement
Invoke-Build -File .\build.ps1 WatcherWatch
```

## Plugin System Architecture

The system dynamically discovers and loads plugins from `plugins/*/Plugin.psm1`:

```
build.ps1 (orchestrator)
  ├── Loads config/toolstack.config.json
  ├── Discovers plugins/ directory
  ├── Imports each Plugin.psm1
  └── Executes Register-Plugin() function
       └── Each plugin defines InvokeBuild tasks
```

### Plugin Structure

Every plugin follows this pattern:

```powershell
# plugins/{PluginName}/Plugin.psm1
param()
function Register-Plugin {
  param($Context, $BuildRoot)

  # Import common interfaces for helpers like Invoke-Quiet
  Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

  # Define InvokeBuild tasks
  task TaskName {
    Write-Host "==> Doing something" -ForegroundColor Cyan
    # Task implementation
  }
}
Export-ModuleMember -Function Register-Plugin
```

### Available Plugins

| Plugin | Purpose | Key Tasks |
|--------|---------|-----------|
| **NpmTools** | Install npm global packages | `NpmInstall` |
| **PipxTools** | Install Python CLI tools via pipx | `PipxInstall` |
| **Pinning** | Enforce exact package versions | `Pin.Report`, `Pin.Sync` |
| **Update** | Check/update global CLIs | `Update.Check`, `Update.All` |
| **CentralizeConfig** | Route configs to C:\Tools | `CentralizeApply` |
| **MasterBin** | Generate PATH wrapper shims | `MasterBin.Rebuild`, `MasterBin.Clean` |
| **Watcher** | Monitor/enforce cache centralization | `WatcherEnforce`, `WatcherWatch` |
| **Scanner** | Find duplicate files + misplaced caches | `Scan.Report` |
| **Secrets** | DPAPI-based secret storage | `Secrets.Set`, `Secrets.Get`, `Secrets.List`, `Secrets.ExportEnv` |
| **Audit** | Event 4663 file access alerting | `Audit.InstallAlerts`, `Audit.RemoveAlerts`, `Audit.TestAlert` |
| **AuditAlert** | Register scheduled tasks for auditing | `AuditSetup` |
| **HealthCheck** | Environment sanity check | `Health.Check` |

## Configuration

Edit `config/toolstack.config.json` to customize:

### Core Paths
```json
{
  "ToolsRoot": "C:\\Tools",
  "CentralCache": "C:\\Tools\\cache",
  "WatchRoots": ["C:\\Users\\richg\\Projects", "D:\\Work"]
}
```

### Package Management
```json
{
  "PipxApps": [
    "invoke", "aider-chat", "ruff", "black", "isort",
    "pylint", "mypy", "pyright", "pytest", "nox",
    "pre-commit", "uv", "langgraph-cli"
  ],
  "NpmGlobal": [
    "@google/generative-ai-cli",
    "@anthropic-ai/claude-code",
    "@google/jules",
    "eslint",
    "prettier"
  ]
}
```

### Version Pinning
```json
{
  "Pins": {
    "pipx": {
      "ruff": "0.14.1",
      "black": "25.9.0"
    },
    "npm": {
      "@anthropic-ai/claude-code": "2.0.31",
      "eslint": "9.39.0"
    }
  }
}
```

### MasterBin (PATH Wrapper System)
```json
{
  "MasterBin": {
    "Enable": false,        // Set true to activate
    "Path": "C:\\Tools\\bin",
    "Sources": [
      "C:\\Tools\\pipx\\bin",
      "C:\\Tools\\node\\npm",
      "C:\\Tools\\pnpm\\bin"
    ],
    "Priority": ["pipx", "npm", "pnpm"],
    "DenyList": ["node", "python", "npm"]  // Don't wrap these
  }
}
```

## Common Workflows

### Adding New CLI Tools

**Python CLIs (via pipx):**
1. Add package name to `config/toolstack.config.json` → `PipxApps` array
2. Run: `Invoke-Build -File .\build.ps1 PipxInstall`

**Node.js CLIs (via npm global):**
1. Add package to `config/toolstack.config.json` → `NpmGlobal` array
2. Run: `Invoke-Build -File .\build.ps1 NpmInstall`

### Pinning Package Versions

**Purpose:** Prevent unwanted updates, ensure consistency across machines

```powershell
# Check current vs desired versions
Invoke-Build -File .\build.ps1 Pin.Report

# Enforce exact versions from config
Invoke-Build -File .\build.ps1 Pin.Sync
```

### Managing Secrets

Uses Windows DPAPI for user-scoped encryption:

```powershell
# Store a secret (prompts for value)
Invoke-Build -File .\build.ps1 Secrets.Set -Name OPENAI_API_KEY

# List all stored secrets (keys only)
Invoke-Build -File .\build.ps1 Secrets.List

# Retrieve secret to clipboard
Invoke-Build -File .\build.ps1 Secrets.Get -Name OPENAI

# Export all secrets as environment variables for current session
Invoke-Build -File .\build.ps1 Secrets.ExportEnv
```

Secrets stored in: `%LOCALAPPDATA%\CLI_Vault\vault.json` (encrypted)

### Updating Global Packages

```powershell
# Generate updates.json report (shows available updates)
Invoke-Build -File .\build.ps1 Update.Check

# Update all global packages (npm update -g + pipx upgrade --all)
Invoke-Build -File .\build.ps1 Update.All
```

### Scanning for Duplicates & Misplaced Caches

```powershell
# Scan configured WatchRoots for:
#  - Duplicate files (by hash)
#  - Misplaced cache/config dirs (.ruff_cache, .mypy_cache, etc.)
Invoke-Build -File .\build.ps1 Scan.Report

# Creates duplicates.json + misplaced.json in %LOCALAPPDATA%\CLI_Reports
```

### Configuration Centralization

**Goal:** Prevent config/cache proliferation in every project directory

```powershell
# One-time setup: route configs to C:\Tools
Invoke-Build -File .\build.ps1 CentralizeApply

# Real-time monitoring (runs until Ctrl+C)
Invoke-Build -File .\build.ps1 WatcherWatch
```

**What it does:**
- Sets XDG_CONFIG_HOME, XDG_CACHE_HOME, XDG_DATA_HOME
- Centralizes caches for pip, npm, pnpm, ruff, black, mypy, uv, eslint
- Optional: Creates wrappers in C:\Tools\bin (if `MasterBin.Enable: true`)

**Environment variables set:**
```
XDG_CONFIG_HOME=C:\Tools\config
XDG_CACHE_HOME=C:\Tools\cache
XDG_DATA_HOME=C:\Tools\data
PIP_CACHE_DIR=C:\Tools\cache\pip
NPM_CONFIG_CACHE=C:\Tools\cache\npm
RUFF_CACHE_DIR=C:\Tools\cache\ruff
BLACK_CACHE_DIR=C:\Tools\cache\black
MYPY_CACHE_DIR=C:\Tools\cache\mypy
UV_CACHE_DIR=C:\Tools\cache\uv
PYTHONPYCACHEPREFIX=C:\Tools\cache\pyc
```

## Environment Integration

This system integrates with the wider Windows environment documented in `C:\Users\richg\ENVIRONMENT_DOCUMENTATION.md`:

### PATH Priority (User scope)
1. `C:\Users\richg\.local\bin` (HIGHEST - user-managed)
2. `C:\Tools\node\pnpm`
3. `C:\Tools\pipx\bin`
4. `C:\Tools\node\npm`
5. Python/system paths follow

### Tool Installation Matrix

| Tool | Install Method | Executable Path |
|------|---------------|-----------------|
| aider | pipx | `C:\Tools\pipx\bin\aider.exe` |
| claude-code | npm global | `C:\Tools\node\npm\claude-code` |
| gemini | npm global | `C:\Tools\node\npm\gemini` |
| gh | installer | `C:\Program Files\GitHub CLI\gh.exe` |
| git | installer | `C:\Program Files\Git\cmd\git.exe` |
| python | installer | `C:\Users\richg\AppData\Local\Programs\Python\Python312\python.exe` |
| ollama | winget | `C:\Users\richg\AppData\Local\Programs\Ollama\ollama.exe` |

### Canonical Config Locations

| Tool | Config Path |
|------|-------------|
| Claude Code | `C:\Users\richg\.claude\` |
| Aider | `C:\Users\richg\.aider.conf.yml` |
| Ollama | `C:\Users\richg\.ollama\` |
| Git (global) | `C:\Users\richg\.gitconfig` |

## Helper Scripts

Located in `scripts/`:

| Script | Purpose |
|--------|---------|
| `centralize_cli_config.ps1` | Sets XDG env vars, builds wrappers (run standalone or via `CentralizeApply` task) |
| `ConfigCache_Enforcer.ps1` | Filesystem watcher that enforces cache centralization in real-time |
| `rebuild_dev_stack.ps1` | Legacy full environment rebuild script |
| `gitignore_global.txt` | Template for global gitignore |

## Plugin Development

### Creating a New Plugin

1. **Create plugin directory:**
   ```powershell
   mkdir plugins\MyPlugin
   ```

2. **Create `Plugin.psm1`:**
   ```powershell
   # plugins/MyPlugin/Plugin.psm1
   param()
   function Register-Plugin {
     param($Context, $BuildRoot)
     Import-Module (Join-Path $BuildRoot "plugins\Common\Plugin.Interfaces.psm1") -Force

     task MyTask {
       Say "Running MyTask"
       # Access config via $Context
       $toolsRoot = $Context.ToolsRoot
       # Use Invoke-Quiet for command execution
       Invoke-Quiet "echo Hello"
       Ok "MyTask complete"
     }
   }
   Export-ModuleMember -Function Register-Plugin
   ```

3. **Add task dependencies** (if needed) in `build.ps1`:
   ```powershell
   task Bootstrap -Depends PipxInstall, NpmInstall, CentralizeApply, MyTask
   ```

### Common Plugin Helpers

Available via `plugins\Common\Plugin.Interfaces.psm1`:

```powershell
# Execute command with error handling
Invoke-Quiet "npm install -g eslint"

# Status messages (defined in build.ps1)
Say "Starting process" "Cyan"   # ==> Starting process
Ok "Success!"                    # ✔ Success!
Warn "Warning message"           # ⚠ Warning message
```

## Design Principles

1. **Centralization over Duplication**
   - One canonical location per tool/cache
   - Enforced via watchers and environment variables

2. **Declarative Configuration**
   - All settings in `toolstack.config.json`
   - No hardcoded paths in plugins

3. **Idempotency**
   - Tasks can be run multiple times safely
   - No side effects from repeated execution

4. **Modularity**
   - Plugins are independent, self-contained
   - Easy to add/remove functionality

5. **Windows-First**
   - Leverages PowerShell 7, DPAPI, Windows paths
   - CMD wrappers for cross-shell compatibility

## Troubleshooting

### Verify Core Tools
```powershell
Invoke-Build -File .\build.ps1 Verify
```
Checks versions of: git, node, python, gh, pwsh, pipx, pnpm, aider, ruff, black, langgraph, gemini, claude-code, copilot

### Check Environment Health
```powershell
Invoke-Build -File .\build.ps1 Health.Check
# Creates health.json in %LOCALAPPDATA%\CLI_Reports
```

### Reset Configuration Centralization
```powershell
# Re-run centralization setup
pwsh -ExecutionPolicy Bypass -File .\scripts\centralize_cli_config.ps1

# With wrapper generation
pwsh -ExecutionPolicy Bypass -File .\scripts\centralize_cli_config.ps1 -BuildWrappers

# Open NEW terminal to apply changes
```

### Debug Plugin Loading
Add debug output to `build.ps1` after the plugin import loop to see which plugins loaded successfully.

## Related Projects (User Workspace)

This repository is part of a larger ecosystem:

- **AI_MANGER** (this repo): CLI tool management and centralization
- **MOD/AUTO_VERSIONING_MOD**: Autonomous code modification system with versioning contracts
- **MOD/ENV_MOD**: Environment setup and parallel build orchestration
- **MOD/planning_MOD**: LLM-orchestrated planning and git worktree strategies

All MOD directories use Git with standardized `.gitignore` and `.gitattributes` (LF for source, CRLF for Windows scripts).

## Performance Notes

- **Bootstrap task**: 2-5 minutes (installs all packages)
- **Pin.Sync**: 1-3 minutes (upgrades/downgrades packages)
- **Scan.Report**: Varies with WatchRoots size (can be slow on large directories)
- **WatcherWatch**: Minimal overhead (runs in background)

## Quick Reference

| Task | Command |
|------|---------|
| Full rebuild | `Invoke-Build -File .\build.ps1` |
| Install packages | `Invoke-Build -File .\build.ps1 Bootstrap` |
| Verify tools | `Invoke-Build -File .\build.ps1 Verify` |
| Pin versions | `Invoke-Build -File .\build.ps1 Pin.Sync` |
| Update all packages | `Invoke-Build -File .\build.ps1 Update.All` |
| Store secret | `Invoke-Build -File .\build.ps1 Secrets.Set -Name KEY_NAME` |
| Get secret | `Invoke-Build -File .\build.ps1 Secrets.Get -Name KEY_NAME` |
| Scan for duplicates | `Invoke-Build -File .\build.ps1 Scan.Report` |
| Start watcher | `Invoke-Build -File .\build.ps1 WatcherWatch` |
| Health check | `Invoke-Build -File .\build.ps1 Health.Check` |
| Rebuild wrappers | `Invoke-Build -File .\build.ps1 MasterBin.Rebuild` |
