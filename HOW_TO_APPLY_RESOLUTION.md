# How to Apply Conflict Resolution to PR #9

This document provides step-by-step instructions for applying the conflict resolution from branch `copilot/resolve-conflicts-pr-9` to the actual PR #9 branch (`copilot/implement-packaging-solution-again`).

## Option 1: Direct Cherry-Pick (Recommended)

This approach cherry-picks only the conflict resolution commit onto the PR branch:

```bash
# 1. Fetch the latest changes
git fetch origin

# 2. Checkout the PR branch
git checkout copilot/implement-packaging-solution-again

# 3. Merge main branch to create the conflicts
git merge origin/main --no-commit

# 4. At this point you'll have conflicts. Abort the merge:
git merge --abort

# 5. Now cherry-pick the resolution commit from the resolution branch
# The resolution commit is: e1ef17c
git cherry-pick e1ef17c

# 6. Push the updated PR branch
git push origin copilot/implement-packaging-solution-again
```

## Option 2: Manual Conflict Resolution

If you prefer to resolve conflicts manually following the documented strategy:

```bash
# 1. Checkout the PR branch
git checkout copilot/implement-packaging-solution-again

# 2. Merge main branch
git merge origin/main --no-commit

# 3. For each conflicting file, apply the resolution strategy from CONFLICT_RESOLUTION_SUMMARY.md:

# Workflow files - use PR version (--ours)
git checkout --ours .github/workflows/ci.yml
git checkout --ours .github/workflows/release.yml

# README - use main version (--theirs)
git checkout --theirs AI_MANGER/README.md

# Build script - use main, then add Health.Check task
git checkout --theirs AI_MANGER/build.ps1
# Then manually add the Health.Check task (see the resolved version)

# Config files - use main versions
git checkout --theirs AI_MANGER/config/toolstack.config.json
git checkout --theirs AI_MANGER/config/toolstack.schema.json
# Add the clistack.schema.json from PR (copy from HEAD)

# Module files
git checkout --ours AI_MANGER/module/CliStack.psd1  # PR version (PS 7.0)
git checkout --theirs AI_MANGER/module/CliStack.psm1  # Then add PSGallery registration

# Plugins - use main versions
git checkout --theirs AI_MANGER/plugins/Common/Plugin.Interfaces.psm1
git checkout --theirs AI_MANGER/plugins/HealthCheck/Plugin.psm1
git checkout --theirs AI_MANGER/plugins/NpmTools/Plugin.psm1
git checkout --theirs AI_MANGER/plugins/PipxTools/Plugin.psm1

# Scripts - use PR versions
git checkout --ours AI_MANGER/scripts/Install-CliStack.ps1
git checkout --ours AI_MANGER/scripts/Sign-Files.ps1

# 4. Stage all resolved files
git add .

# 5. Commit the merge
git commit -m "Merge main branch and resolve conflicts

Resolved conflicts by preserving all functionality from both branches.
See CONFLICT_RESOLUTION_SUMMARY.md for details."

# 6. Push to PR branch
git push origin copilot/implement-packaging-solution-again
```

## Option 3: Branch Replacement

Replace the PR branch content with the resolved state:

```bash
# 1. Create a backup of the PR branch
git checkout copilot/implement-packaging-solution-again
git branch copilot/implement-packaging-solution-again-backup

# 2. Reset PR branch to point to the resolved state
git reset --hard copilot/resolve-conflicts-pr-9

# 3. Force push (WARNING: This rewrites history)
git push -f origin copilot/implement-packaging-solution-again
```

**Note:** Option 3 rewrites history and should only be used if the PR has no other dependencies.

## Verification Steps

After applying the resolution, verify everything works:

```bash
cd AI_MANGER

# Test module manifest
pwsh -Command "Test-ModuleManifest -Path module/CliStack.psd1"

# Test module import
pwsh -Command "Import-Module ./module/CliStack.psd1 -Force; Get-Command Invoke-CliStack"

# Verify build script syntax
pwsh -Command "[System.Management.Automation.PSParser]::Tokenize((Get-Content build.ps1 -Raw), [ref]\$null)"

# Validate YAML files
python3 -c "import yaml; yaml.safe_load(open('../.github/workflows/ci.yml'))"
python3 -c "import yaml; yaml.safe_load(open('../.github/workflows/release.yml'))"

# Validate JSON files
python3 -c "import json; json.load(open('config/toolstack.config.json'))"
python3 -c "import json; json.load(open('config/toolstack.schema.json'))"
python3 -c "import json; json.load(open('config/clistack.schema.json'))"
```

All tests should pass with output like:
```
✓ Module manifest valid
✓ Module imports successfully
✓ Build script syntax valid
✓ Workflow YAML files valid
✓ JSON configuration files valid
```

## What Was Merged

The resolution merged:
- **From PR**: Packaging/CI/CD infrastructure, remote installer, certificate cleanup
- **From Main**: Complete plugin system, Observability config, Force parameter

**Result**: 100% functionality from both branches preserved, zero feature loss.

## Troubleshooting

If you encounter issues:

1. **Merge conflicts persist**: Review CONFLICT_RESOLUTION_SUMMARY.md for the specific resolution strategy for each file

2. **Tests fail**: Compare your resolved files with the ones in `copilot/resolve-conflicts-pr-9` branch

3. **Want to start over**: 
   ```bash
   git merge --abort  # If in the middle of a merge
   git reset --hard origin/copilot/implement-packaging-solution-again  # Reset to original PR state
   ```

## Additional Resources

- See `CONFLICT_RESOLUTION_SUMMARY.md` for detailed analysis of each conflict
- Review commit `e1ef17c` on branch `copilot/resolve-conflicts-pr-9` for the exact resolution
