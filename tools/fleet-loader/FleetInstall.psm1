<#
.SYNOPSIS
  Install a verified fleet snapshot, or one beta zip, into a user folder. Windows PowerShell 5.1. ASCII only.
.DESCRIPTION
  Offline. Nothing is downloaded. A zip is unpacked only after its SHA256 matches the stable manifest or the
  checksum the caller passes for a beta file. A mismatch unpacks nothing. Entries that would write outside the
  destination are refused. Launch starts only System32 powershell.exe or cmd.exe, and only for one .ps1 or .bat
  whose name the caller names. No .exe from a zip is started.
#>
$ErrorActionPreference = 'Stop'

$script:SnapshotModule = Join-Path $PSScriptRoot 'FleetSnapshot.psm1'
if (-not (Get-Command Get-FleetFileSha256 -ErrorAction SilentlyContinue)) {
    Import-Module $script:SnapshotModule -Force -Global
}
Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

$script:InstallSchema = 'edge-ops.fleet-install/1'
$script:MaxEntries = 10000
$script:MaxUncompressedBytes = 2147483648
$script:IdPattern = '^[a-z0-9][a-z0-9-]{0,39}$'
$script:HashPattern = '^[0-9a-fA-F]{64}$'
$script:LauncherPattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,80}\.(ps1|bat)$'

function Get-FleetInstallRoot {
    [CmdletBinding()]
    param([string]$Root = '')
    if ($Root) { return [System.IO.Path]::GetFullPath($Root) }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not set. Pass -Root.' }
    return [System.IO.Path]::GetFullPath((Join-Path (Join-Path $env:LOCALAPPDATA 'FleetHacker') 'apps'))
}

function Test-FleetPathUnder {
    param([string]$Root, [string]$Candidate)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $r = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $c = [System.IO.Path]::GetFullPath($Candidate)
    if ([string]::Equals($c, $r, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $c.StartsWith($r + $sep, [StringComparison]::OrdinalIgnoreCase)
}

function Test-FleetReparsePoint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
    $link = $item.PSObject.Properties['LinkType']
    if ($null -ne $link -and $link.Value) { return $true }
    return $false
}

function Test-FleetZipEntryName {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name) -or $Name.Length -gt 400) { return $false }
    if ($Name -match '[\x00-\x1f]') { return $false }
    $norm = $Name.Replace('\', '/')
    if ($norm.StartsWith('/') -or $norm.Contains(':')) { return $false }
    $trim = $norm.TrimEnd('/')
    if (-not $trim) { return $false }
    foreach ($part in $trim.Split('/')) {
        if (-not $part -or $part -eq '.' -or $part -eq '..') { return $false }
        if ($part.Length -gt 180) { return $false }
        if ($part.EndsWith(' ') -or $part.EndsWith('.')) { return $false }
    }
    return $true
}

function Expand-FleetZip {
    <#
    .SYNOPSIS
      Unpacks a zip into an empty directory. Refuses a path that escapes the directory, a link, or a size cap.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [long]$MaxUncompressedBytes = $script:MaxUncompressedBytes,
        [int]$MaxEntries = $script:MaxEntries
    )
    if (Test-Path -LiteralPath $Destination) { throw "Destination already exists: $Destination" }
    if (Test-FleetReparsePoint -Path $ZipPath) { throw 'Zip is a link, not a file.' }
    New-Item -ItemType Directory -Path $Destination | Out-Null
    $destRoot = [System.IO.Path]::GetFullPath($Destination)
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead(([System.IO.Path]::GetFullPath($ZipPath)))
        $count = 0
        $total = [long]0
        foreach ($entry in $archive.Entries) {
            $count++
            if ($count -gt $MaxEntries) { throw 'Zip has too many entries.' }
            $name = [string]$entry.FullName
            if (-not (Test-FleetZipEntryName $name)) { throw "Refused zip entry '$name'." }
            $length = [long]$entry.Length
            if ($length -lt 0) { throw "Refused zip entry '$name'." }
            $total += $length
            if ($length -gt $MaxUncompressedBytes -or $total -gt $MaxUncompressedBytes) { throw 'Zip expands past the size cap.' }
            $norm = $name.Replace('\', '/').TrimEnd('/')
            $target = $destRoot
            foreach ($part in $norm.Split('/')) { $target = Join-Path $target $part }
            $target = [System.IO.Path]::GetFullPath($target)
            if (-not (Test-FleetPathUnder -Root $destRoot -Candidate $target)) { throw "Refused zip entry '$name'." }
            $isDir = $name.EndsWith('/') -or $name.EndsWith('\')
            if ($isDir) {
                if (Test-FleetReparsePoint -Path $target) { throw "Refused link at '$name'." }
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                continue
            }
            $parent = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            if (Test-FleetReparsePoint -Path $parent) { throw "Refused link at '$name'." }
            $inStream = $entry.Open()
            $outStream = $null
            try {
                $outStream = [System.IO.File]::Create($target)
                $inStream.CopyTo($outStream)
            }
            finally {
                if ($outStream) { $outStream.Dispose() }
                $inStream.Dispose()
            }
            $written = (Get-Item -LiteralPath $target -Force).Length
            if ($written -ne $length) { throw "Entry '$name' wrote $written bytes, the zip says $length." }
            if (Test-FleetReparsePoint -Path $target) { throw "Refused link at '$name'." }
        }
        if ($count -lt 1) { throw 'Zip has no entries.' }
    }
    catch {
        if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }
    finally {
        if ($archive) { $archive.Dispose() }
    }
}

function Read-FleetInstallState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $empty = [pscustomobject]@{ Schema = $script:InstallSchema; Tools = @() }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $empty }
    if (Test-FleetReparsePoint -Path $Path) { throw "Install state is a link: $Path" }
    try { $raw = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json }
    catch { throw "Install state is not valid JSON: $Path" }
    if ($null -eq $raw -or $raw -is [System.Array]) { throw "Install state must be a JSON object: $Path" }
    $schema = $raw.PSObject.Properties['schema']
    if ($null -eq $schema -or [string]$schema.Value -ne $script:InstallSchema) { throw "Unsupported install state schema in $Path" }
    $tools = @()
    $tp = $raw.PSObject.Properties['tools']
    if ($null -ne $tp -and $null -ne $tp.Value) { $tools = @($tp.Value) }
    [pscustomobject]@{ Schema = $script:InstallSchema; Tools = $tools }
}

function Write-FleetInstallState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$State)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tools = @()
    foreach ($t in @($State.Tools)) {
        $tools += [ordered]@{
            id = [string]$t.id; channel = [string]$t.channel; snapshot = [string]$t.snapshot
            tag = [string]$t.tag; asset = [string]$t.asset; sha256 = ([string]$t.sha256).ToLowerInvariant()
            installedAt = [string]$t.installedAt; relativePath = [string]$t.relativePath
        }
    }
    $out = [ordered]@{ schema = $script:InstallSchema; tools = $tools }
    $json = $out | ConvertTo-Json -Depth 6
    $tmp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    Move-Item -LiteralPath $tmp -Destination $Path
}

function Get-FleetToolRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Id)
    $state = Read-FleetInstallState -Path (Join-Path $Root 'install-state.json')
    foreach ($t in @($state.Tools)) { if ([string]$t.id -eq $Id) { return $t } }
    $null
}

function Set-FleetToolRecord {
    param($Root, $Record)
    $path = Join-Path $Root 'install-state.json'
    $state = Read-FleetInstallState -Path $path
    $kept = @()
    foreach ($t in @($state.Tools)) { if ([string]$t.id -ne [string]$Record.id) { $kept += $t } }
    $kept += $Record
    Write-FleetInstallState -Path $path -State ([pscustomobject]@{ Tools = $kept })
}

function Install-FleetZipAt {
    param([string]$ZipPath, [string]$DestDir, [long]$MaxUncompressedBytes, [int]$MaxEntries)
    $parent = Split-Path -Parent $DestDir
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (Test-FleetReparsePoint -Path $parent) { throw "Install folder is a link: $parent" }
    $stagingParent = Join-Path $parent '.staging'
    if (-not (Test-Path -LiteralPath $stagingParent)) { New-Item -ItemType Directory -Path $stagingParent | Out-Null }
    $staging = Join-Path $stagingParent ((Split-Path -Leaf $DestDir) + '-' + [guid]::NewGuid().ToString('N'))
    Expand-FleetZip -ZipPath $ZipPath -Destination $staging -MaxUncompressedBytes $MaxUncompressedBytes -MaxEntries $MaxEntries
    $trash = $null
    try {
        if (Test-Path -LiteralPath $DestDir) {
            if (Test-FleetReparsePoint -Path $DestDir) { throw "Install folder is a link: $DestDir" }
            $trash = Join-Path $parent ('.trash-' + [guid]::NewGuid().ToString('N'))
            Move-Item -LiteralPath $DestDir -Destination $trash
        }
        Move-Item -LiteralPath $staging -Destination $DestDir
    }
    catch {
        if ($trash -and (Test-Path -LiteralPath $trash) -and -not (Test-Path -LiteralPath $DestDir)) {
            Move-Item -LiteralPath $trash -Destination $DestDir
            $trash = $null
        }
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }
    if ($trash -and (Test-Path -LiteralPath $trash)) { Remove-Item -LiteralPath $trash -Recurse -Force }
}

function New-FleetInstallResult {
    param([bool]$Ok, [string[]]$Errors, [string[]]$Installed)
    [pscustomobject]@{ Ok = $Ok; Errors = @($Errors); Installed = @($Installed) }
}

function Install-FleetSnapshot {
    <#
    .SYNOPSIS
      Verifies a stable manifest, then unpacks every pinned zip. A failed check unpacks nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$AssetDir,
        [string]$Root = '',
        [string]$CatalogPath = '',
        [long]$MaxUncompressedBytes = $script:MaxUncompressedBytes,
        [int]$MaxEntries = $script:MaxEntries
    )
    $errors = New-Object 'System.Collections.Generic.List[string]'
    try { $rootFull = Get-FleetInstallRoot -Root $Root }
    catch { return (New-FleetInstallResult $false @($_.Exception.Message) @()) }
    $check = Test-FleetSnapshot -ManifestPath $ManifestPath -AssetDir $AssetDir -CatalogPath $CatalogPath
    if (-not $check.Ok) {
        foreach ($e in @($check.Errors)) { $errors.Add([string]$e) }
        return (New-FleetInstallResult $false $errors.ToArray() @())
    }
    $staged = New-Object System.Collections.Generic.List[object]
    $assetRoot = [System.IO.Path]::GetFullPath($AssetDir)
    try {
        foreach ($t in @($check.Results)) {
            if ([string]$t.Status -ne 'Ok') { throw "Refusing to unpack $($t.Id)." }
            $zip = Join-Path $assetRoot ([string]$t.Asset)
            $stagingParent = Join-Path $rootFull '.staging'
            if (-not (Test-Path -LiteralPath $stagingParent)) { New-Item -ItemType Directory -Path $stagingParent -Force | Out-Null }
            $staging = Join-Path $stagingParent ([string]$t.Id + '-' + [guid]::NewGuid().ToString('N'))
            Expand-FleetZip -ZipPath $zip -Destination $staging -MaxUncompressedBytes $MaxUncompressedBytes -MaxEntries $MaxEntries
            $staged.Add([pscustomobject]@{ Id = [string]$t.Id; Staging = $staging; Asset = [string]$t.Asset; Sha = [string]$t.Expected })
        }
    }
    catch {
        foreach ($s in $staged) {
            if (Test-Path -LiteralPath $s.Staging) { Remove-Item -LiteralPath $s.Staging -Recurse -Force -ErrorAction SilentlyContinue }
        }
        $errors.Add($_.Exception.Message)
        return (New-FleetInstallResult $false $errors.ToArray() @())
    }
    $read = Read-FleetSnapshotManifest -Path $ManifestPath
    $byId = @{}
    foreach ($tool in @($read.Manifest.tools)) { $byId[[string]$tool.id] = $tool }
    $installed = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($s in $staged) {
            $dest = Join-Path $rootFull $s.Id
            $parent = Split-Path -Parent $dest
            $trash = $null
            if (Test-Path -LiteralPath $dest) {
                if (Test-FleetReparsePoint -Path $dest) { throw "Install folder is a link: $dest" }
                $trash = Join-Path $parent ('.trash-' + [guid]::NewGuid().ToString('N'))
                Move-Item -LiteralPath $dest -Destination $trash
            }
            try { Move-Item -LiteralPath $s.Staging -Destination $dest }
            catch {
                if ($trash -and (Test-Path -LiteralPath $trash) -and -not (Test-Path -LiteralPath $dest)) {
                    Move-Item -LiteralPath $trash -Destination $dest
                }
                throw
            }
            if ($trash -and (Test-Path -LiteralPath $trash)) { Remove-Item -LiteralPath $trash -Recurse -Force }
            $meta = $byId[$s.Id]
            $now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            Set-FleetToolRecord -Root $rootFull -Record ([pscustomobject]@{
                id = $s.Id; channel = 'stable'; snapshot = [string]$read.Manifest.snapshot
                tag = [string]$meta.tag; asset = $s.Asset; sha256 = $s.Sha; installedAt = $now; relativePath = $s.Id
            })
            $installed.Add($s.Id)
        }
    }
    catch {
        $errors.Add($_.Exception.Message)
        foreach ($s in $staged) {
            if ($s.Staging -and (Test-Path -LiteralPath $s.Staging)) {
                Remove-Item -LiteralPath $s.Staging -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        return (New-FleetInstallResult $false $errors.ToArray() $installed.ToArray())
    }
    New-FleetInstallResult $true @() $installed.ToArray()
}

function Install-FleetToolBeta {
    <#
    .SYNOPSIS
      Unpacks one zip after it matches the published checksum the caller passes. Does not contact the network.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Tag,
        [string]$Root = '',
        [long]$MaxUncompressedBytes = $script:MaxUncompressedBytes,
        [int]$MaxEntries = $script:MaxEntries
    )
    if ($Id -notmatch $script:IdPattern) { return (New-FleetInstallResult $false @('Tool id is not valid.') @()) }
    if ($ExpectedSha256 -notmatch $script:HashPattern) { return (New-FleetInstallResult $false @('Checksum must be 64 hex digits.') @()) }
    if ($Tag -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { return (New-FleetInstallResult $false @('Tag is not valid.') @()) }
    try { $rootFull = Get-FleetInstallRoot -Root $Root }
    catch { return (New-FleetInstallResult $false @($_.Exception.Message) @()) }
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { return (New-FleetInstallResult $false @("Zip not found: $ZipPath") @()) }
    $want = $ExpectedSha256.ToLowerInvariant()
    $actual = (Get-FleetFileSha256 -Path $ZipPath).ToLowerInvariant()
    if ($actual -ne $want) {
        return (New-FleetInstallResult $false @("SHA256 is $actual, the published checksum is $want. Not unpacked.") @())
    }
    try {
        Install-FleetZipAt -ZipPath $ZipPath -DestDir (Join-Path $rootFull $Id) -MaxUncompressedBytes $MaxUncompressedBytes -MaxEntries $MaxEntries
        $now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        Set-FleetToolRecord -Root $rootFull -Record ([pscustomobject]@{
            id = $Id; channel = 'beta'; snapshot = ''; tag = $Tag
            asset = [System.IO.Path]::GetFileName($ZipPath); sha256 = $want; installedAt = $now; relativePath = $Id
        })
    }
    catch { return (New-FleetInstallResult $false @($_.Exception.Message) @()) }
    New-FleetInstallResult $true @() @($Id)
}

function Switch-FleetToolToStable {
    <#
    .SYNOPSIS
      Reinstalls one tool from the pinned snapshot and records the channel as stable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$AssetDir,
        [string]$Root = '',
        [long]$MaxUncompressedBytes = $script:MaxUncompressedBytes,
        [int]$MaxEntries = $script:MaxEntries
    )
    if ($Id -notmatch $script:IdPattern) { return (New-FleetInstallResult $false @('Tool id is not valid.') @()) }
    try { $rootFull = Get-FleetInstallRoot -Root $Root }
    catch { return (New-FleetInstallResult $false @($_.Exception.Message) @()) }
    $read = Read-FleetSnapshotManifest -Path $ManifestPath
    if (-not $read.Valid) { return (New-FleetInstallResult $false @($read.Errors) @()) }
    $tool = $null
    foreach ($t in @($read.Manifest.tools)) { if ([string]$t.id -eq $Id) { $tool = $t } }
    if (-not $tool) { return (New-FleetInstallResult $false @("Tool '$Id' is not in the snapshot.") @()) }
    $zip = Join-Path ([System.IO.Path]::GetFullPath($AssetDir)) ([string]$tool.asset)
    if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) { return (New-FleetInstallResult $false @("Pinned asset missing: $zip") @()) }
    $want = ([string]$tool.sha256).ToLowerInvariant()
    $actual = (Get-FleetFileSha256 -Path $zip).ToLowerInvariant()
    if ($actual -ne $want) { return (New-FleetInstallResult $false @("SHA256 is $actual, the manifest says $want. Not unpacked.") @()) }
    $bytes = $tool.PSObject.Properties['bytes']
    if ($null -ne $bytes -and $null -ne $bytes.Value) {
        $len = (Get-Item -LiteralPath $zip -Force).Length
        if ([long]$bytes.Value -ne $len) { return (New-FleetInstallResult $false @("Size is $len, the manifest says $($bytes.Value). Not unpacked.") @()) }
    }
    try {
        Install-FleetZipAt -ZipPath $zip -DestDir (Join-Path $rootFull $Id) -MaxUncompressedBytes $MaxUncompressedBytes -MaxEntries $MaxEntries
        $now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        Set-FleetToolRecord -Root $rootFull -Record ([pscustomobject]@{
            id = $Id; channel = 'stable'; snapshot = [string]$read.Manifest.snapshot
            tag = [string]$tool.tag; asset = [string]$tool.asset; sha256 = $want; installedAt = $now; relativePath = $Id
        })
    }
    catch { return (New-FleetInstallResult $false @($_.Exception.Message) @()) }
    New-FleetInstallResult $true @() @($Id)
}

function Install-FleetBundle {
    <#
    .SYNOPSIS
      Installs an air-gapped bundle zip (snapshot.json plus assets\) after the caller-supplied checksum matches.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BundleZip,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [string]$Root = '',
        [string]$CatalogPath = '',
        [long]$MaxUncompressedBytes = $script:MaxUncompressedBytes,
        [int]$MaxEntries = $script:MaxEntries
    )
    if ($ExpectedSha256 -notmatch $script:HashPattern) { return (New-FleetInstallResult $false @('Checksum must be 64 hex digits.') @()) }
    if (-not (Test-Path -LiteralPath $BundleZip -PathType Leaf)) { return (New-FleetInstallResult $false @("Bundle not found: $BundleZip") @()) }
    $want = $ExpectedSha256.ToLowerInvariant()
    $actual = (Get-FleetFileSha256 -Path $BundleZip).ToLowerInvariant()
    if ($actual -ne $want) { return (New-FleetInstallResult $false @("Bundle SHA256 is $actual, the published checksum is $want. Not unpacked.") @()) }
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ('fleetbundle-' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-FleetZip -ZipPath $BundleZip -Destination $temp -MaxUncompressedBytes $MaxUncompressedBytes -MaxEntries $MaxEntries
        $manifest = Join-Path $temp 'snapshot.json'
        $assets = Join-Path $temp 'assets'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return (New-FleetInstallResult $false @('Bundle has no snapshot.json.') @()) }
        if (-not (Test-Path -LiteralPath $assets -PathType Container)) { return (New-FleetInstallResult $false @('Bundle has no assets folder.') @()) }
        return (Install-FleetSnapshot -ManifestPath $manifest -AssetDir $assets -Root $Root -CatalogPath $CatalogPath -MaxUncompressedBytes $MaxUncompressedBytes -MaxEntries $MaxEntries)
    }
    catch { return (New-FleetInstallResult $false @($_.Exception.Message) @()) }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Resolve-FleetLauncher {
    <#
    .SYNOPSIS
      Finds the one named .ps1 or .bat under an install folder. Refuses any other extension, a link, or two matches.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$LauncherName
    )
    if ($LauncherName -notmatch $script:LauncherPattern) { return $null }
    if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) { return $null }
    if (Test-FleetReparsePoint -Path $InstallDir) { return $null }
    $root = [System.IO.Path]::GetFullPath($InstallDir)
    $found = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        if ($f.Name -eq $LauncherName) { $found += $f.FullName }
    }
    if ($found.Count -ne 1) { return $null }
    $full = [System.IO.Path]::GetFullPath($found[0])
    if (-not (Test-FleetPathUnder -Root $root -Candidate $full)) { return $null }
    # FileInfo has Directory, not Parent. DirectoryInfo has Parent. Walk either until the install root.
    $cur = Get-Item -LiteralPath $full -Force
    while ($null -ne $cur) {
        if (($cur.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
        $link = $cur.PSObject.Properties['LinkType']
        if ($null -ne $link -and $link.Value) { return $null }
        $here = $cur.FullName.TrimEnd('\', '/')
        if ([string]::Equals($here, $root.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { return $full }
        if (-not (Test-FleetPathUnder -Root $root -Candidate $cur.FullName)) { return $null }
        if ($cur -is [System.IO.FileInfo]) { $cur = $cur.Directory } else { $cur = $cur.Parent }
    }
    $null
}

function Start-FleetTool {
    <#
    .SYNOPSIS
      Starts the named launcher with System32 powershell.exe or cmd.exe. -DryRun returns that command and starts nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$LauncherName,
        [string]$Root = '',
        [switch]$DryRun
    )
    if ($Id -notmatch $script:IdPattern) {
        return [pscustomobject]@{ Ok = $false; Code = 'E_ARGS'; Message = 'Tool id is not valid.'; Exe = $null; Arguments = @(); Launcher = $null }
    }
    try { $rootFull = Get-FleetInstallRoot -Root $Root }
    catch { return [pscustomobject]@{ Ok = $false; Code = 'E_ARGS'; Message = $_.Exception.Message; Exe = $null; Arguments = @(); Launcher = $null } }
    $dir = Join-Path $rootFull $Id
    $launcher = Resolve-FleetLauncher -InstallDir $dir -LauncherName $LauncherName
    if (-not $launcher) {
        return [pscustomobject]@{ Ok = $false; Code = 'E_ARGS'; Message = 'Launcher must be one .ps1 or .bat under the install folder.'; Exe = $null; Arguments = @(); Launcher = $null }
    }
    $ext = [System.IO.Path]::GetExtension($launcher).ToLowerInvariant()
    # A string, not Join-Path: this host may not have a C: drive, and DryRun must still name the Windows program.
    $sys = $env:SystemRoot
    if (-not $sys) { $sys = 'C:\Windows' }
    $sys = $sys.TrimEnd('\', '/')
    if ($ext -eq '.ps1') {
        $exe = $sys + '\System32\WindowsPowerShell\v1.0\powershell.exe'
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcher)
    }
    elseif ($ext -eq '.bat') {
        $exe = $sys + '\System32\cmd.exe'
        $argList = @('/d', '/c', $launcher)
    }
    else {
        return [pscustomobject]@{ Ok = $false; Code = 'E_ARGS'; Message = 'Launcher extension is not allowed.'; Exe = $null; Arguments = @(); Launcher = $null }
    }
    if ($DryRun) {
        return [pscustomobject]@{ Ok = $true; Code = 'OK'; Message = 'dry run'; Exe = $exe; Arguments = $argList; Launcher = $launcher }
    }
    if ($env:OS -ne 'Windows_NT' -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        return [pscustomobject]@{ Ok = $false; Code = 'E_UNSUPPORTED'; Message = 'Windows PowerShell 5.1 is required to launch.'; Exe = $exe; Arguments = $argList; Launcher = $launcher }
    }
    $p = Start-Process -FilePath $exe -ArgumentList $argList -WorkingDirectory (Split-Path -Parent $launcher) -PassThru
    [pscustomobject]@{ Ok = $true; Code = 'OK'; Message = 'started'; Exe = $exe; Arguments = $argList; Launcher = $launcher; ProcessId = $p.Id }
}

Export-ModuleMember -Function Get-FleetInstallRoot, Test-FleetZipEntryName, Expand-FleetZip, Read-FleetInstallState, Write-FleetInstallState,
    Get-FleetToolRecord, Install-FleetSnapshot, Install-FleetToolBeta, Switch-FleetToolToStable, Install-FleetBundle,
    Resolve-FleetLauncher, Start-FleetTool
