@{
    RootModule        = 'CliStack.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'c6a8c1a7-1a20-4d8a-9e23-2c76f9b8b9b1'
    Author            = 'AI_MANGER maintainers'
    CompanyName       = 'AI_MANGER'
    Copyright         = '(c) AI_MANGER'
    Description       = 'CLI stack module with InvokeBuild entrypoints and packaging helpers.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Invoke-CliStack')
    CmdletsToExport   = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('InvokeBuild','Packaging','CLI')
            ProjectUri = 'https://github.com/DICKY1987/AI_MANGER'
            ReleaseNotes = 'Initial module scaffolding'
        }
    }
}
