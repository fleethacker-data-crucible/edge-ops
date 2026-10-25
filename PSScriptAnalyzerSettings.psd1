# FleetHacker shared PSScriptAnalyzer settings (Windows PowerShell 5.1 target).
# Usage: Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
@{
    Severity     = @('Error', 'Warning')
    IncludeDefaultRules = $true
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'   # console tools print status to the host on purpose
    )
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @('win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework')
        }
        # Legacy cmdlet-compat rule keyed by the classic 5.1 profile id.
        PSUseCompatibleCmdlets = @{
            compatibility = @('desktop-5.1.14393.206-windows')
        }
        PSUseCompatibleTypes = @{
            Enable         = $true
            TargetProfiles = @('win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework')
        }
        PSAvoidUsingCmdletAliases       = @{ Enable = $true }
        PSUseBOMForUnicodeEncodedFile   = @{ Enable = $true }
    }
}
