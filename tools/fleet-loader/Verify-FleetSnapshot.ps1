<#
.SYNOPSIS
  Verifies the packaged assets of a fleet snapshot against its manifest. Offline: reads local files only.
.DESCRIPTION
  Windows PowerShell 5.1 or PowerShell 7. Fails closed: exit code 0 only when the manifest is valid and every
  pinned asset is present and matches its SHA256 (and size, when the manifest gives one). Anything else exits 1.
  Verification only: nothing is downloaded, unpacked or run.
.PARAMETER Manifest
  Path to the snapshot manifest (fleet-snapshot.schema.json describes it).
.PARAMETER AssetDir
  Folder that holds the downloaded zips, named as in the manifest.
.PARAMETER Catalog
  Optional catalog.json. When given, every tool id and repo in the manifest must match it.
.PARAMETER Json
  Print one JSON result instead of text lines.
.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\fleet-loader\Verify-FleetSnapshot.ps1 -Manifest .\snapshot.json -AssetDir D:\fleet\assets -Catalog .\catalog.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Manifest,
    [Parameter(Mandatory = $true)][string]$AssetDir,
    [string]$Catalog = '',
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'FleetSnapshot.psm1') -Force
    $r = Test-FleetSnapshot -ManifestPath $Manifest -AssetDir $AssetDir -CatalogPath $Catalog
}
catch {
    # Any unexpected failure counts as a failed verification.
    $r = [pscustomobject]@{ Ok = $false; Errors = @("Verification could not run: $($_.Exception.Message)"); Results = @() }
}
if ($Json) {
    $out = [ordered]@{ schema = 'edge-ops.fleet-verify/1'; ok = [bool]$r.Ok; errors = @($r.Errors); results = @($r.Results) }
    [Console]::Out.WriteLine(($out | ConvertTo-Json -Depth 6))
}
else {
    foreach ($x in @($r.Results)) { Write-Host ('{0,-14} {1,-34} {2}' -f $x.Status, $x.Asset, $x.Id) }
    foreach ($e in @($r.Errors)) { Write-Host "ERROR: $e" }
    if ($r.Ok) { Write-Host "OK: every asset matches the manifest." } else { Write-Host 'FAILED: do not unpack or run anything from this set.' }
}
if ($r.Ok) { exit 0 } else { exit 1 }
