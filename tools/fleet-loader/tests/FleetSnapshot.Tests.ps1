# Pester 5. Runs on Windows PowerShell 5.1 and pwsh. Local fake assets only: no network, no real Releases.
BeforeAll {
    $script:Loader = Split-Path -Parent $PSScriptRoot
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $Loader)
    Import-Module (Join-Path $Loader 'FleetSnapshot.psm1') -Force
    $script:Verify = Join-Path $Loader 'Verify-FleetSnapshot.ps1'
    $script:HostExe = (Get-Process -Id $PID).Path

    function New-Work {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ('fleetsnap-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $d 'assets') | Out-Null
        return $d
    }
    # Writes a fake zip (just bytes) and returns its manifest entry.
    function New-FakeAsset([string]$Work, [string]$Id, [string]$Repo, [string]$Tag, [int]$Size) {
        $name = "$Id-$Tag.zip"
        $bytes = New-Object byte[] $Size
        (New-Object System.Random ($Id.GetHashCode())).NextBytes($bytes)
        [System.IO.File]::WriteAllBytes((Join-Path $Work "assets\$name"), $bytes)
        $sha = Get-FleetFileSha256 -Path (Join-Path $Work "assets\$name")
        [ordered]@{ id = $Id; repo = $Repo; tag = $Tag; asset = $name; sha256 = $sha; bytes = $Size }
    }
    function Copy-Entry($Entry) { $c = [ordered]@{}; foreach ($k in $Entry.Keys) { $c[$k] = $Entry[$k] }; return $c }
    function Write-Manifest([string]$Work, $Tools, [hashtable]$Override = @{}) {
        $m = [ordered]@{ schema = 'edge-ops.fleet-snapshot/1'; snapshot = 'test'; channel = 'stable'; created = '2026-10-31T00:00:00Z'; tools = @($Tools) }
        foreach ($k in $Override.Keys) { if ($null -eq $Override[$k]) { $m.Remove($k) } else { $m[$k] = $Override[$k] } }
        $path = Join-Path $Work 'snapshot.json'
        [System.IO.File]::WriteAllText($path, ($m | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
        return $path
    }
    function New-Set([string]$Work) {
        @((New-FakeAsset $Work 'capstan' 'fleethacker-data-crucible/Capstan' 'v0.1.0' 2048),
          (New-FakeAsset $Work 'snapshackle' 'fleethacker-data-crucible/SnapShackle' 'v0.4.0' 4096))
    }
}

Describe 'Test-FleetSnapshot with local fake assets' {
    BeforeEach { $script:W = New-Work; $script:Tools = New-Set $W }
    AfterEach { Remove-Item $W -Recurse -Force -ErrorAction SilentlyContinue }

    It 'passes when every asset matches' {
        $r = Test-FleetSnapshot -ManifestPath (Write-Manifest $W $Tools) -AssetDir (Join-Path $W 'assets')
        $r.Ok | Should -BeTrue
        @($r.Results).Count | Should -Be 2
        @($r.Results | Where-Object { $_.Status -ne 'Ok' }).Count | Should -Be 0
    }
    It 'accepts an upper-case hash and ignores extra files in the folder' {
        $Tools[0].sha256 = $Tools[0].sha256.ToUpperInvariant()
        Set-Content -LiteralPath (Join-Path $W 'assets\notes.txt') -Value 'not in the manifest'
        (Test-FleetSnapshot -ManifestPath (Write-Manifest $W $Tools) -AssetDir (Join-Path $W 'assets')).Ok | Should -BeTrue
    }
    It 'fails closed when one byte of an asset changes' {
        $p = Join-Path $W 'assets\capstan-v0.1.0.zip'
        $b = [System.IO.File]::ReadAllBytes($p); $b[10] = [byte](($b[10] + 1) % 256); [System.IO.File]::WriteAllBytes($p, $b)
        $r = Test-FleetSnapshot -ManifestPath (Write-Manifest $W $Tools) -AssetDir (Join-Path $W 'assets')
        $r.Ok | Should -BeFalse
        ($r.Results | Where-Object { $_.Id -eq 'capstan' }).Status | Should -Be 'HashMismatch'
        ($r.Results | Where-Object { $_.Id -eq 'snapshackle' }).Status | Should -Be 'Ok'
    }
    It 'fails closed on a missing asset' {
        Remove-Item (Join-Path $W 'assets\snapshackle-v0.4.0.zip')
        $r = Test-FleetSnapshot -ManifestPath (Write-Manifest $W $Tools) -AssetDir (Join-Path $W 'assets')
        $r.Ok | Should -BeFalse
        ($r.Results | Where-Object { $_.Id -eq 'snapshackle' }).Status | Should -Be 'Missing'
    }
    It 'fails closed on a size mismatch, before hashing' {
        $Tools[0].bytes = 1
        $r = Test-FleetSnapshot -ManifestPath (Write-Manifest $W $Tools) -AssetDir (Join-Path $W 'assets')
        $r.Ok | Should -BeFalse
        ($r.Results | Where-Object { $_.Id -eq 'capstan' }).Status | Should -Be 'SizeMismatch'
    }
    It 'fails closed when a folder stands in for the asset' {
        Remove-Item (Join-Path $W 'assets\capstan-v0.1.0.zip')
        New-Item -ItemType Directory -Path (Join-Path $W 'assets\capstan-v0.1.0.zip') | Out-Null
        $r = Test-FleetSnapshot -ManifestPath (Write-Manifest $W $Tools) -AssetDir (Join-Path $W 'assets')
        $r.Ok | Should -BeFalse
        ($r.Results | Where-Object { $_.Id -eq 'capstan' }).Status | Should -Be 'NotAFile'
    }
    It 'fails when the asset folder or the manifest does not exist' {
        (Test-FleetSnapshot -ManifestPath (Write-Manifest $W $Tools) -AssetDir (Join-Path $W 'nope')).Ok | Should -BeFalse
        (Test-FleetSnapshot -ManifestPath (Join-Path $W 'nope.json') -AssetDir (Join-Path $W 'assets')).Ok | Should -BeFalse
    }
}

Describe 'Manifest checks (invalid manifests are refused, nothing is hashed)' {
    BeforeEach { $script:W = New-Work; $script:Tools = New-Set $W }
    AfterEach { Remove-Item $W -Recurse -Force -ErrorAction SilentlyContinue }

    It 'refuses text that is not JSON' {
        $p = Join-Path $W 'snapshot.json'; Set-Content -LiteralPath $p -Value '{ not json'
        (Read-FleetSnapshotManifest -Path $p).Valid | Should -BeFalse
        (Test-FleetSnapshot -ManifestPath $p -AssetDir (Join-Path $W 'assets')).Ok | Should -BeFalse
    }
    It 'refuses a JSON list at the top level' {
        $p = Join-Path $W 'snapshot.json'; Set-Content -LiteralPath $p -Value '[1,2]'
        (Read-FleetSnapshotManifest -Path $p).Valid | Should -BeFalse
    }
    It 'refuses an unknown schema version, a beta channel, and unknown fields' {
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W $Tools @{ schema = 'edge-ops.fleet-snapshot/2' })).Valid | Should -BeFalse
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W $Tools @{ channel = 'beta' })).Valid | Should -BeFalse
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W $Tools @{ extra = 1 })).Valid | Should -BeFalse
        $Tools[0].url = 'https://example.invalid/x.zip'
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W $Tools)).Valid | Should -BeFalse
    }
    It 'refuses a missing required field and an empty tool list' {
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W $Tools @{ created = $null })).Valid | Should -BeFalse
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W @())).Valid | Should -BeFalse
        $Tools[1].Remove('sha256')
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W $Tools)).Valid | Should -BeFalse
    }
    It 'refuses fields that are present but null' {
        $p = Write-Manifest $W $Tools
        $json = Get-Content -Raw -LiteralPath $p
        $nullHash = $json -replace ('"sha256":\s*"' + $Tools[0].sha256 + '"'), '"sha256": null'
        $nullHash | Should -Not -Be $json
        Set-Content -LiteralPath $p -Value $nullHash
        (Read-FleetSnapshotManifest -Path $p).Valid | Should -BeFalse
        Set-Content -LiteralPath $p -Value ($json -replace '"created":\s*"[^"]*"', '"created": null')
        (Read-FleetSnapshotManifest -Path $p).Valid | Should -BeFalse
        Set-Content -LiteralPath $p -Value ($json -replace '"tools":\s*\[', '"tools": null, "x": [')
        (Test-FleetSnapshot -ManifestPath $p -AssetDir (Join-Path $W 'assets')).Ok | Should -BeFalse
    }
    It 'refuses an asset name with a folder part or a bad extension' {
        foreach ($bad in @('..\evil.zip', '../evil.zip', 'sub/x.zip', 'C:\x.zip', 'x.exe', '.hidden.zip', ' x.zip')) {
            $t = Copy-Entry $Tools[0]; $t.asset = $bad
            (Read-FleetSnapshotManifest -Path (Write-Manifest $W @($t))).Valid | Should -BeFalse -Because "asset '$bad' must be refused"
        }
    }
    It 'refuses a bad hash, repeated ids, repeated assets and a bad repo' {
        $t = Copy-Entry $Tools[0]; $t.sha256 = 'abc123'
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W @($t))).Valid | Should -BeFalse
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W @($Tools[0], $Tools[0]))).Valid | Should -BeFalse
        $t = Copy-Entry $Tools[1]; $t.asset = $Tools[0].asset
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W @($Tools[0], $t))).Valid | Should -BeFalse
        $t = Copy-Entry $Tools[0]; $t.repo = 'not a repo'
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W @($t))).Valid | Should -BeFalse
    }
    It 'refuses a bytes value that is not a whole number' {
        $t = Copy-Entry $Tools[0]; $t.bytes = 'big'
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W @($t))).Valid | Should -BeFalse
        $t.bytes = 0
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W @($t))).Valid | Should -BeFalse
    }
    It 'checks tool ids and repos against catalog.json when asked' {
        $catalog = Join-Path $RepoRoot 'catalog.json'
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W $Tools) -CatalogPath $catalog).Valid | Should -BeTrue
        $t = Copy-Entry $Tools[0]; $t.id = 'no-such-tool'
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W @($t)) -CatalogPath $catalog).Valid | Should -BeFalse
        $t = Copy-Entry $Tools[0]; $t.repo = 'fleethacker-data-crucible/Other'
        (Read-FleetSnapshotManifest -Path (Write-Manifest $W @($t)) -CatalogPath $catalog).Valid | Should -BeFalse
    }
}

Describe 'Verify-FleetSnapshot.ps1 (exit codes)' {
    BeforeEach { $script:W = New-Work; $script:Tools = New-Set $W }
    AfterEach { Remove-Item $W -Recurse -Force -ErrorAction SilentlyContinue }

    It 'exits 0 when everything matches' {
        $m = Write-Manifest $W $Tools
        & $HostExe -NoProfile -ExecutionPolicy Bypass -File $Verify -Manifest $m -AssetDir (Join-Path $W 'assets') | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
    It 'exits 1 on a hash mismatch and says not to unpack' {
        $p = Join-Path $W 'assets\snapshackle-v0.4.0.zip'
        $b = [System.IO.File]::ReadAllBytes($p); $b[0] = [byte](($b[0] + 1) % 256); [System.IO.File]::WriteAllBytes($p, $b)
        $m = Write-Manifest $W $Tools
        $out = (& $HostExe -NoProfile -ExecutionPolicy Bypass -File $Verify -Manifest $m -AssetDir (Join-Path $W 'assets')) -join "`n"
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'HashMismatch'
        $out | Should -Match 'do not unpack'
    }
    It 'exits 1 for a missing manifest and prints JSON on request' {
        $out = (& $HostExe -NoProfile -ExecutionPolicy Bypass -File $Verify -Manifest (Join-Path $W 'nope.json') -AssetDir (Join-Path $W 'assets') -Json) -join "`n"
        $LASTEXITCODE | Should -Be 1
        $j = $out | ConvertFrom-Json
        $j.schema | Should -Be 'edge-ops.fleet-verify/1'
        $j.ok | Should -BeFalse
    }
}

Describe 'Shipped example and schema' {
    It 'the example manifest is well formed, and verifying it against real assets fails closed' {
        $ex = Join-Path $Loader 'fleet-snapshot.example.json'
        $r = Read-FleetSnapshotManifest -Path $ex -CatalogPath (Join-Path $RepoRoot 'catalog.json')
        $r.Errors | Should -BeNullOrEmpty
        $r.Valid | Should -BeTrue
        $w = New-Work
        try {
            New-Item -ItemType File -Path (Join-Path $w 'assets\SnapShackle-v0.0.0.zip') | Out-Null
            (Test-FleetSnapshot -ManifestPath $ex -AssetDir (Join-Path $w 'assets')).Ok | Should -BeFalse
        } finally { Remove-Item $w -Recurse -Force }
    }
    It 'the schema file declares what the script enforces' {
        $s = Get-FleetSnapshotSchema
        $s.properties.schema.const | Should -Be 'edge-ops.fleet-snapshot/1'
        $s.properties.channel.const | Should -Be 'stable'
        $s.'$defs'.tool.required | Should -Contain 'sha256'
        $s.'$defs'.tool.additionalProperties | Should -BeFalse
    }
}
