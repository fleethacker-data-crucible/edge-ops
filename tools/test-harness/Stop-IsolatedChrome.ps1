<#
.SYNOPSIS
    Wrapper: stops an isolated Chrome (only processes using its profile) and deletes the profile.
.EXAMPLE
    .\Stop-IsolatedChrome.ps1 -ProfilePath $c.ProfilePath
#>
[CmdletBinding()]
param([Parameter(ValueFromPipeline)]$Instance, [string]$ProfilePath, [switch]$KeepProfile)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'FleetTestHarness.psm1') -Force
if (-not $Instance) { $Instance = [pscustomobject]@{ ProfilePath = $ProfilePath } }
Stop-IsolatedChrome -Instance $Instance -KeepProfile:$KeepProfile
