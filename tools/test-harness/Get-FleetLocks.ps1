<#
.SYNOPSIS
    Shows current FleetHacker leases (C:\ProgramData\fleethacker\locks) with an IsStale column.
#>
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'FleetTestHarness.psm1') -Force
Get-FleetLocks | Format-Table -AutoSize
