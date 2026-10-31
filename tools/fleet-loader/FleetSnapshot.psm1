<#
.SYNOPSIS
  Offline checks for a fleet snapshot manifest and the packaged assets it pins (edge-ops issue 34).
.DESCRIPTION
  Windows PowerShell 5.1 and PowerShell 7. Reads local files only: no download, no network, no unpacking.
  The manifest format is fleet-snapshot.schema.json beside this file; the patterns and limits used here come
  from that file, so the schema and the checks cannot drift apart.
  Fails closed: a manifest that is not valid, a missing asset, a wrong size or a wrong SHA256 each make
  the whole result not OK. Nothing is "partly verified".
#>
$ErrorActionPreference = 'Stop'

$script:SchemaPath = Join-Path $PSScriptRoot 'fleet-snapshot.schema.json'

function Get-FleetSnapshotSchema {
    [CmdletBinding()]
    param([string]$Path = $script:SchemaPath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Fleet snapshot schema not found: $Path" }
    [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
}

# Under StrictMode a missing property throws, so read optional properties through PSObject.Properties.
function Get-FleetProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return ,$p.Value
}

function Test-FleetPattern {
    param($Value, $Rule, [string]$Label, [System.Collections.Generic.List[string]]$Errors)
    if (-not ($Value -is [string])) { $Errors.Add("$Label must be text."); return $false }
    $max = Get-FleetProp $Rule 'maxLength'
    if ($null -ne $max -and $Value.Length -gt [int]$max) { $Errors.Add("$Label is longer than $max characters."); return $false }
    $pat = Get-FleetProp $Rule 'pattern'
    if ($pat -and -not [regex]::IsMatch($Value, [string]$pat)) { $Errors.Add("$Label has an invalid value '$Value'."); return $false }
    return $true
}

function Read-FleetSnapshotManifest {
    <#
    .SYNOPSIS
      Reads and checks a manifest. Returns Valid, Errors (all of them) and Manifest (null when the file cannot be parsed).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$CatalogPath = ''
    )
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $manifest = $null
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $errors.Add("Manifest not found: $Path")
        return [pscustomobject]@{ Valid = $false; Errors = $errors.ToArray(); Manifest = $null }
    }
    try { $manifest = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json }
    catch { $errors.Add("Manifest is not valid JSON: $($_.Exception.Message)") }
    if ($null -eq $manifest -or $manifest -is [System.Array] -or $manifest -isnot [System.Management.Automation.PSCustomObject]) {
        if ($errors.Count -eq 0) { $errors.Add('Manifest must be a JSON object.') }
        return [pscustomobject]@{ Valid = $false; Errors = $errors.ToArray(); Manifest = $null }
    }

    $schema = Get-FleetSnapshotSchema
    $toolRule = $schema.'$defs'.tool

    # Top level: required fields, no unknown fields.
    foreach ($req in $schema.required) {
        $rp = $manifest.PSObject.Properties[$req]
        if ($null -eq $rp) { $errors.Add("Missing field '$req'.") }
        elseif ($null -eq $rp.Value) { $errors.Add("Field '$req' must have a value.") }
    }
    foreach ($p in $manifest.PSObject.Properties) {
        if ($null -eq $schema.properties.PSObject.Properties[$p.Name]) { $errors.Add("Unknown field '$($p.Name)'.") }
    }
    $v = Get-FleetProp $manifest 'schema'
    if ($null -ne $v -and $v -ne $schema.properties.schema.const) { $errors.Add("Unsupported schema '$v' (this script reads $($schema.properties.schema.const)).") }
    $v = Get-FleetProp $manifest 'channel'
    if ($null -ne $v -and $v -ne $schema.properties.channel.const) { $errors.Add("Unsupported channel '$v' (a manifest describes the $($schema.properties.channel.const) channel).") }
    $v = Get-FleetProp $manifest 'snapshot'
    if ($null -ne $v) { [void](Test-FleetPattern $v $schema.properties.snapshot 'snapshot' $errors) }
    $v = Get-FleetProp $manifest 'created'
    if ($null -ne $v) { [void](Test-FleetPattern $v $schema.properties.created 'created' $errors) }
    $v = Get-FleetProp $manifest 'notes'
    if ($null -ne $v) { [void](Test-FleetPattern $v $schema.properties.notes 'notes' $errors) }

    # Tools.
    $toolsProp = $manifest.PSObject.Properties['tools']; $tools = $null; if ($null -ne $toolsProp) { $tools = $toolsProp.Value }
    if ($null -ne $toolsProp) {
        $list = @($tools)
        if ($tools -isnot [System.Array]) { $errors.Add("'tools' must be a list.") }
        elseif ($list.Count -lt [int]$schema.properties.tools.minItems) { $errors.Add("'tools' must hold at least $($schema.properties.tools.minItems) entry.") }
        elseif ($list.Count -gt [int]$schema.properties.tools.maxItems) { $errors.Add("'tools' holds more than $($schema.properties.tools.maxItems) entries.") }
        $seen = @{ id = @{}; repo = @{}; asset = @{} }
        $n = 0
        foreach ($t in $list) {
            $n++
            $label = "tools[$n]"
            if ($t -isnot [System.Management.Automation.PSCustomObject]) { $errors.Add("$label must be an object."); continue }
            foreach ($req in $toolRule.required) {
                $rp = $t.PSObject.Properties[$req]
                if ($null -eq $rp) { $errors.Add("$label is missing '$req'.") }
                elseif ($null -eq $rp.Value) { $errors.Add("$label.$req must have a value.") }
            }
            foreach ($p in $t.PSObject.Properties) {
                if ($null -eq $toolRule.properties.PSObject.Properties[$p.Name]) { $errors.Add("$label has an unknown field '$($p.Name)'.") }
            }
            foreach ($f in @('id', 'repo', 'tag', 'asset', 'sha256')) {
                $val = Get-FleetProp $t $f
                if ($null -eq $val) { continue }
                $ok = Test-FleetPattern $val $toolRule.properties.$f "$label.$f" $errors
                if ($ok -and $seen.ContainsKey($f)) {
                    $key = ([string]$val).ToLowerInvariant()
                    if ($seen[$f].ContainsKey($key)) { $errors.Add("$label.$f '$val' is used twice.") } else { $seen[$f][$key] = $true }
                }
            }
            $b = Get-FleetProp $t 'bytes'
            if ($null -ne $b) {
                $okInt = ($b -is [int] -or $b -is [long]) -and [long]$b -ge [long]$toolRule.properties.bytes.minimum
                if (-not $okInt) { $errors.Add("$label.bytes must be a whole number of at least $($toolRule.properties.bytes.minimum).") }
            }
        }
    }

    # Optional: every tool must be in the hub catalog, with the same repo.
    if ($CatalogPath) {
        if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) { $errors.Add("Catalog not found: $CatalogPath") }
        else {
            $catalog = [System.IO.File]::ReadAllText($CatalogPath) | ConvertFrom-Json
            $byId = @{}
            foreach ($c in $catalog.tools) { $byId[[string]$c.id] = $c }
            foreach ($t in @($tools)) {
                $id = [string](Get-FleetProp $t 'id'); $repo = [string](Get-FleetProp $t 'repo')
                if (-not $id) { continue }
                if (-not $byId.ContainsKey($id)) { $errors.Add("Tool '$id' is not in the catalog."); continue }
                $want = ([string]$byId[$id].repo) -replace '^https://github\.com/', ''
                if ($repo -and $repo.ToLowerInvariant() -ne $want.ToLowerInvariant()) { $errors.Add("Tool '$id' names repo '$repo' but the catalog says '$want'.") }
            }
        }
    }
    [pscustomobject]@{ Valid = ($errors.Count -eq 0); Errors = $errors.ToArray(); Manifest = $manifest }
}

function Get-FleetFileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::OpenRead($Path)
    try { $bytes = $sha.ComputeHash($fs) } finally { $fs.Dispose(); $sha.Dispose() }
    (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Test-FleetSnapshot {
    <#
    .SYNOPSIS
      Checks every asset the manifest pins against the files in AssetDir. Never unpacks or downloads anything.
    .OUTPUTS
      Ok (true only when the manifest is valid and every asset is present and matches), Errors, Results (one per tool:
      Id, Asset, Status Ok|Missing|NotAFile|SizeMismatch|HashMismatch|Skipped, Expected, Actual).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$AssetDir,
        [string]$CatalogPath = ''
    )
    $read = Read-FleetSnapshotManifest -Path $ManifestPath -CatalogPath $CatalogPath
    $errors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($e in $read.Errors) { $errors.Add($e) }
    $results = New-Object 'System.Collections.Generic.List[object]'
    if (-not $read.Valid) {
        return [pscustomobject]@{ Ok = $false; Errors = $errors.ToArray(); Results = @() }
    }
    if (-not (Test-Path -LiteralPath $AssetDir -PathType Container)) {
        $errors.Add("Asset folder not found: $AssetDir")
        return [pscustomobject]@{ Ok = $false; Errors = $errors.ToArray(); Results = @() }
    }
    $root = [System.IO.Path]::GetFullPath($AssetDir).TrimEnd('\', '/')
    foreach ($t in @($read.Manifest.tools)) {
        $id = [string]$t.id; $asset = [string]$t.asset; $want = ([string]$t.sha256).ToLowerInvariant()
        $status = 'Ok'; $actual = ''
        $full = [System.IO.Path]::GetFullPath((Join-Path $root $asset))
        # The schema already refuses any folder part in `asset`; this is the second lock.
        if ([System.IO.Path]::GetDirectoryName($full) -ne $root) {
            $status = 'NotAFile'; $errors.Add("$id`: asset '$asset' is outside the asset folder.")
        }
        elseif (-not (Test-Path -LiteralPath $full)) { $status = 'Missing'; $errors.Add("$id`: $asset is missing.") }
        elseif (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $status = 'NotAFile'; $errors.Add("$id`: $asset is not a file.") }
        else {
            $item = Get-Item -LiteralPath $full -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $status = 'NotAFile'; $errors.Add("$id`: $asset is a link, not a file.")
            }
            else {
                $bytes = Get-FleetProp $t 'bytes'
                if ($null -ne $bytes -and [long]$bytes -ne $item.Length) {
                    $status = 'SizeMismatch'; $actual = [string]$item.Length
                    $errors.Add("$id`: $asset is $($item.Length) bytes, the manifest says $bytes.")
                }
                else {
                    $actual = Get-FleetFileSha256 -Path $full
                    if ($actual -ne $want) { $status = 'HashMismatch'; $errors.Add("$id`: $asset has SHA256 $actual, the manifest says $want.") }
                }
            }
        }
        $results.Add([pscustomobject]@{ Id = $id; Asset = $asset; Status = $status; Expected = $want; Actual = $actual })
    }
    [pscustomobject]@{ Ok = ($errors.Count -eq 0 -and $results.Count -ge 1); Errors = $errors.ToArray(); Results = $results.ToArray() }
}

Export-ModuleMember -Function Get-FleetSnapshotSchema, Read-FleetSnapshotManifest, Get-FleetFileSha256, Test-FleetSnapshot
