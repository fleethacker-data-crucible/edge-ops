<#
.SYNOPSIS
  Installs a verified fleet snapshot from local files. Offline: nothing is downloaded or launched.
.DESCRIPTION
  Windows PowerShell 5.1 or PowerShell 7. Exit 0 only when every pinned zip matched and was unpacked.
  A failed check unpacks nothing and exits 1.
.PARAMETER Manifest
  Path to the snapshot manifest.
.PARAMETER AssetDir
  Folder of zip files named as in the manifest.
.PARAMETER Root
  Install folder. Defaults to %LOCALAPPDATA%\FleetHacker\apps.
.PARAMETER Catalog
  Optional catalog.json. When given, every tool must match it.
.PARAMETER Json
  Print one JSON result.
.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\fleet-loader\Install-FleetSnapshot.ps1 -Manifest .\snapshot.json -AssetDir D:\fleet\assets -Root "$env:LOCALAPPDATA\FleetHacker\apps"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Manifest,
    [Parameter(Mandatory = $true)][string]$AssetDir,
    [string]$Root = '',
    [string]$Catalog = '',
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'FleetInstall.psm1') -Force
    $r = Install-FleetSnapshot -ManifestPath $Manifest -AssetDir $AssetDir -Root $Root -CatalogPath $Catalog
}
catch {
    $r = [pscustomobject]@{ Ok = $false; Errors = @("Install could not run: $($_.Exception.Message)"); Installed = @() }
}
if ($Json) {
    $out = [ordered]@{ schema = 'edge-ops.fleet-install-result/1'; ok = [bool]$r.Ok; errors = @($r.Errors); installed = @($r.Installed) }
    [Console]::Out.WriteLine(($out | ConvertTo-Json -Depth 6))
}
else {
    foreach ($e in @($r.Errors)) { Write-Host "ERROR: $e" }
    if ($r.Ok) { Write-Host ("OK: installed {0}." -f (@($r.Installed) -join ', ')) }
    else { Write-Host 'FAILED: nothing new was unpacked from a set that did not verify.' }
}
if ($r.Ok) { exit 0 } else { exit 1 }
