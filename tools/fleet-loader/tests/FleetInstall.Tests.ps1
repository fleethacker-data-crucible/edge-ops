# Pester 5. Runs on Windows PowerShell 5.1 and pwsh. Local fake zips only: no network.
BeforeAll {
    $script:Loader = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $Loader 'FleetInstall.psm1') -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    function New-Work {
        $d = Join-Path ([System.IO.Path]::GetTempPath()) ('fleetinst-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $d 'assets') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $d 'root') | Out-Null
        return $d
    }
    function New-ToolZip([string]$Path, [hashtable]$Files) {
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Files.Keys) {
                $entry = $zip.CreateEntry($name)
                $writer = New-Object System.IO.StreamWriter($entry.Open())
                try { $writer.Write([string]$Files[$name]) } finally { $writer.Dispose() }
            }
        }
        finally { $zip.Dispose() }
    }
    function New-Asset([string]$Work, [string]$Id, [string]$Body) {
        $name = "$Id-v1.0.0.zip"
        $path = Join-Path $Work "assets\$name"
        New-ToolZip $path @{ "Launch-$Id.bat" = "@echo off`r`n"; 'readme.txt' = $Body }
        $sha = Get-FleetFileSha256 -Path $path
        [ordered]@{ id = $Id; repo = "fleethacker-data-crucible/$Id"; tag = 'v1.0.0'; asset = $name; sha256 = $sha; bytes = (Get-Item -LiteralPath $path).Length }
    }
    function Write-Manifest([string]$Work, $Tools) {
        $m = [ordered]@{ schema = 'edge-ops.fleet-snapshot/1'; snapshot = 'test-snap'; channel = 'stable'; created = '2026-11-14T00:00:00Z'; tools = @($Tools) }
        $path = Join-Path $Work 'snapshot.json'
        [System.IO.File]::WriteAllText($path, ($m | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
        return $path
    }
}

Describe 'Install-FleetSnapshot' {
    BeforeEach { $script:W = New-Work }
    AfterEach { Remove-Item $W -Recurse -Force -ErrorAction SilentlyContinue }

    It 'unpacks a matching snapshot and records the stable channel' {
        $tools = @((New-Asset $W 'capstan' 'stable-body'), (New-Asset $W 'scrimshaw' 'other'))
        $r = Install-FleetSnapshot -ManifestPath (Write-Manifest $W $tools) -AssetDir (Join-Path $W 'assets') -Root (Join-Path $W 'root')
        $r.Ok | Should -BeTrue
        @($r.Installed).Count | Should -Be 2
        [System.IO.File]::ReadAllText((Join-Path $W 'root\capstan\readme.txt')) | Should -Be 'stable-body'
        (Get-FleetToolRecord -Root (Join-Path $W 'root') -Id 'capstan').channel | Should -Be 'stable'
        (Get-FleetToolRecord -Root (Join-Path $W 'root') -Id 'capstan').snapshot | Should -Be 'test-snap'
    }

    It 'unpacks nothing when one asset hash does not match' {
        $tools = @((New-Asset $W 'capstan' 'stable-body'))
        $tools[0].sha256 = ('ab' * 32)
        $r = Install-FleetSnapshot -ManifestPath (Write-Manifest $W $tools) -AssetDir (Join-Path $W 'assets') -Root (Join-Path $W 'root')
        $r.Ok | Should -BeFalse
        Test-Path (Join-Path (Join-Path $W 'root') 'capstan') | Should -BeFalse
        Test-Path (Join-Path (Join-Path $W 'root') 'install-state.json') | Should -BeFalse
    }

    It 'refuses a zip entry that escapes the install folder' {
        $zip = Join-Path $W 'assets\slip.zip'
        New-ToolZip $zip @{ '../escaped.txt' = 'nope'; 'readme.txt' = 'inside' }
        $dest = Join-Path $W 'root\slip-out'
        { Expand-FleetZip -ZipPath $zip -Destination $dest } | Should -Throw
        Test-Path $dest | Should -BeFalse
        Test-Path (Join-Path (Join-Path $W 'root') 'escaped.txt') | Should -BeFalse
        Test-Path (Join-Path $W 'escaped.txt') | Should -BeFalse
    }

    It 'stops when the expanded size cap is exceeded and leaves no folder' {
        $zip = Join-Path $W 'assets\small.zip'
        New-ToolZip $zip @{ 'readme.txt' = '1234567890' }
        $dest = Join-Path $W 'root\capped'
        { Expand-FleetZip -ZipPath $zip -Destination $dest -MaxUncompressedBytes 4 } | Should -Throw
        Test-Path $dest | Should -BeFalse
    }
}

Describe 'beta channel and switch back' {
    BeforeEach { $script:W = New-Work }
    AfterEach { Remove-Item $W -Recurse -Force -ErrorAction SilentlyContinue }

    It 'rejects a beta zip whose checksum does not match and then accepts the real one' {
        $path = Join-Path $W 'assets\beta.zip'
        New-ToolZip $path @{ 'Launch-capstan.bat' = "@echo off`r`n"; 'readme.txt' = 'beta-body' }
        $bad = Install-FleetToolBeta -ZipPath $path -Id 'capstan' -ExpectedSha256 ('cd' * 32) -Tag 'v9.0.0' -Root (Join-Path $W 'root')
        $bad.Ok | Should -BeFalse
        Test-Path (Join-Path (Join-Path $W 'root') 'capstan') | Should -BeFalse
        $sha = Get-FleetFileSha256 -Path $path
        $ok = Install-FleetToolBeta -ZipPath $path -Id 'capstan' -ExpectedSha256 $sha -Tag 'v9.0.0' -Root (Join-Path $W 'root')
        $ok.Ok | Should -BeTrue
        (Get-FleetToolRecord -Root (Join-Path $W 'root') -Id 'capstan').channel | Should -Be 'beta'
        [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $W 'root') 'capstan') 'readme.txt')) | Should -Be 'beta-body'
    }

    It 'switches a beta install back to the pinned snapshot' {
        $stable = New-Asset $W 'capstan' 'stable-body'
        $manifest = Write-Manifest $W @($stable)
        $beta = Join-Path $W 'assets\beta.zip'
        New-ToolZip $beta @{ 'Launch-capstan.bat' = "@echo off`r`n"; 'readme.txt' = 'beta-body' }
        $sha = Get-FleetFileSha256 -Path $beta
        (Install-FleetToolBeta -ZipPath $beta -Id 'capstan' -ExpectedSha256 $sha -Tag 'v9.0.0' -Root (Join-Path $W 'root')).Ok | Should -BeTrue
        $sw = Switch-FleetToolToStable -Id 'capstan' -ManifestPath $manifest -AssetDir (Join-Path $W 'assets') -Root (Join-Path $W 'root')
        $sw.Ok | Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path $W 'root\capstan\readme.txt')) | Should -Be 'stable-body'
        (Get-FleetToolRecord -Root (Join-Path $W 'root') -Id 'capstan').channel | Should -Be 'stable'
    }
}

Describe 'air-gapped bundle' {
    BeforeEach { $script:W = New-Work }
    AfterEach { Remove-Item $W -Recurse -Force -ErrorAction SilentlyContinue }

    It 'installs from a local bundle zip only when its checksum matches' {
        $tool = New-Asset $W 'capstan' 'bundled'
        $manifest = Write-Manifest $W @($tool)
        $stage = Join-Path $W 'stage'
        New-Item -ItemType Directory -Path (Join-Path $stage 'assets') | Out-Null
        Copy-Item -LiteralPath $manifest -Destination (Join-Path $stage 'snapshot.json')
        Copy-Item -LiteralPath (Join-Path $W 'assets\capstan-v1.0.0.zip') -Destination (Join-Path $stage 'assets\capstan-v1.0.0.zip')
        $bundle = Join-Path $W 'bundle.zip'
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $bundle)
        $sha = Get-FleetFileSha256 -Path $bundle
        $bad = Install-FleetBundle -BundleZip $bundle -ExpectedSha256 ('ef' * 32) -Root (Join-Path $W 'root')
        $bad.Ok | Should -BeFalse
        Test-Path (Join-Path (Join-Path $W 'root') 'capstan') | Should -BeFalse
        $ok = Install-FleetBundle -BundleZip $bundle -ExpectedSha256 $sha -Root (Join-Path $W 'root')
        $ok.Ok | Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $W 'root') 'capstan') 'readme.txt')) | Should -Be 'bundled'
    }
}

Describe 'zip swapped after the hash' {
    BeforeEach { $script:W = New-Work }
    AfterEach {
        & (Get-Module FleetInstall) { $script:FleetInstallAfterHashForTest = $null }
        Remove-Item $W -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'refuses the install when the zip changes after the check' {
        $path = Join-Path $W 'assets\beta.zip'
        New-ToolZip $path @{ 'Launch-capstan.bat' = "@echo off`r`n"; 'readme.txt' = 'good-body' }
        $sha = Get-FleetFileSha256 -Path $path
        $hook = {
            param($Source)
            [System.IO.File]::WriteAllBytes($Source, [System.Text.Encoding]::ASCII.GetBytes('swapped-after-check'))
        }
        $mod = Get-Module FleetInstall
        & $mod { param($h) $script:FleetInstallAfterHashForTest = $h } $hook
        $r = Install-FleetToolBeta -ZipPath $path -Id 'capstan' -ExpectedSha256 $sha -Tag 'v9.0.0' -Root (Join-Path $W 'root')
        $r.Ok | Should -BeFalse
        ($r.Errors -join ' ') | Should -Match 'changed after it was checked'
        Test-Path (Join-Path (Join-Path $W 'root') 'capstan') | Should -BeFalse
        $readme = Join-Path (Join-Path (Join-Path $W 'root') 'capstan') 'readme.txt'
        if (Test-Path -LiteralPath $readme) { [System.IO.File]::ReadAllText($readme) | Should -Not -Be 'swapped-after-check' }
    }
}

Describe 'launcher' {
    BeforeEach { $script:W = New-Work }
    AfterEach { Remove-Item $W -Recurse -Force -ErrorAction SilentlyContinue }

    It 'dry-run starts System32 powershell or cmd and refuses an exe or a second match' {
        $dir = Join-Path (Join-Path $W 'root') 'capstan'
        New-Item -ItemType Directory -Path (Join-Path $dir 'inner') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dir 'inner\Launch-capstan.bat'), "@echo off`r`n")
        [System.IO.File]::WriteAllText((Join-Path $dir 'helper.exe'), 'MZ')
        $plan = Start-FleetTool -Id 'capstan' -LauncherName 'Launch-capstan.bat' -Root (Join-Path $W 'root') -DryRun
        $plan.Ok | Should -BeTrue
        $plan.Exe | Should -Match 'System32[\\/]cmd\.exe$'
        $plan.Launcher | Should -Be (Join-Path $dir 'inner\Launch-capstan.bat')
        (Start-FleetTool -Id 'capstan' -LauncherName 'helper.exe' -Root (Join-Path $W 'root') -DryRun).Ok | Should -BeFalse
        [System.IO.File]::WriteAllText((Join-Path $dir 'Launch-capstan.bat'), "@echo off`r`n")
        (Start-FleetTool -Id 'capstan' -LauncherName 'Launch-capstan.bat' -Root (Join-Path $W 'root') -DryRun).Ok | Should -BeFalse
    }

    It 'refuses a launcher that is a link' {
        $dir = Join-Path $W 'root\capstan'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $outside = Join-Path $W 'outside.ps1'
        [System.IO.File]::WriteAllText($outside, "Write-Output 'no'`n")
        $link = Join-Path $dir 'Launch-capstan.ps1'
        try { New-Item -ItemType SymbolicLink -Path $link -Target $outside | Out-Null }
        catch { Set-ItResult -Skipped -Because 'this environment cannot create a symlink' }
        $resolved = Resolve-FleetLauncher -InstallDir $dir -LauncherName 'Launch-capstan.ps1'
        $resolved | Should -BeNullOrEmpty
    }
}
