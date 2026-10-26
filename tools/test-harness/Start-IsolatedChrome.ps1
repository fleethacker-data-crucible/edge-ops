<#
.SYNOPSIS
    Wrapper: launches an isolated Chrome (fresh profile, free debug port 9300-9399). See Get-Help Start-IsolatedChrome -Full.
.EXAMPLE
    $c = .\Start-IsolatedChrome.ps1 -Agent uikit -Headless -Url 'about:blank'
#>
[CmdletBinding()]
param([string]$Agent = 'agent', [string]$RunId, [switch]$Headless, [string]$Url, [string[]]$ExtraArgs = @(), [int]$StartupTimeoutSec = 30)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'FleetTestHarness.psm1') -Force
$p = @{ Agent = $Agent; Headless = $Headless; ExtraArgs = $ExtraArgs; StartupTimeoutSec = $StartupTimeoutSec }
if ($RunId) { $p.RunId = $RunId }
if ($Url) { $p.Url = $Url }
Start-IsolatedChrome @p
