# Pester 5. Mocks stop at the Gangplank boundary: no downloads, no Start-Process, no network.
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $PSScriptRoot '..\Periscope.psm1') -Force
    Import-Module (Join-Path $script:RepoRoot 'tools\fleet-port\FleetPort.psm1') -Force
    $script:Cat = Get-Content -Raw (Join-Path $script:RepoRoot 'catalog.json') | ConvertFrom-Json
    function Get-CatTool([string]$Id) { @($script:Cat.tools) | Where-Object { $_.id -eq $Id } }
}

Describe 'Periscope port block' {
    It 'owns 8803-8805, the first free block after Semaphore, and PORTS.md says so' {
        $b = Get-FleetPortBlock -Tool 'periscope'
        $b.Start | Should -Be 8803
        $b.Size | Should -Be 3
        $b.End | Should -Be 8805
        $b.Policy | Should -Be 'reuse'
        $ports = Get-Content -Raw (Join-Path $script:RepoRoot 'PORTS.md')
        $ports | Should -Match '8803-8805'
    }
}

Describe 'who can be launched' {
    It 'skips support and tools with no root bat, and keeps a tool that has one' {
        Test-PeriscopeLaunchable (Get-CatTool 'halyard-ballast') | Should -BeFalse
        Test-PeriscopeLaunchable (Get-CatTool 'halyard') | Should -BeTrue
        Test-PeriscopeLaunchable (Get-CatTool 'semaphore') | Should -BeTrue
        $bare = [pscustomobject]@{ id = 'custom'; name = 'Custom'; group = 'local-ai'; launcher = ''; repo = 'https://github.com/fleethacker-data-crucible/custom' }
        Test-PeriscopeLaunchable $bare | Should -BeFalse
        (Get-PeriscopeLauncherName 'Launch-Windlass.bat serve --model <file.gguf>') | Should -Be 'Launch-Windlass.bat'
        (Get-PeriscopeLauncherName '..\Launch-Evil.bat') | Should -Be ''
    }
}

Describe 'status and download-status envelopes' {
    It 'says the host is local and names a support tool as not launchable' {
        $e = New-PeriscopeEnvelope 'periscope status' -Result (Get-PeriscopeStatusResult)
        $e.ok | Should -BeTrue
        $e.v | Should -Be 1
        $e.action | Should -Be 'periscope status'
        $e.result.local | Should -BeTrue
        $ballast = Get-PeriscopeStatusResult -Tool (Get-CatTool 'halyard-ballast')
        $ballast.launchable | Should -BeFalse
        $ballast.reason | Should -Be 'support'
    }
    It 'returns an unknown-job envelope for a bad id and the job body when it exists' {
        $missing = Get-PeriscopeDownloadStatus -Jobs @{} -JobId 'nope'
        $missing.ok | Should -BeFalse
        $missing.error.code | Should -Be 'E_NOTFOUND'
        $id = 'job_' + ('ab' * 16)
        $jobs = @{ $id = @{ job = $id; tool = 'halyard'; state = 'downloading'; step = 'Downloading'; percent = 40; message = '' } }
        $hit = Get-PeriscopeDownloadStatus -Jobs $jobs -JobId $id
        $hit.ok | Should -BeTrue
        $hit.v | Should -Be 1
        $hit.result.state | Should -Be 'downloading'
        $hit.result.percent | Should -Be 40
        $hit.result.step | Should -Be 'Downloading'
    }
}

Describe 'click flow (Gangplank boundary mocked)' {
    BeforeEach {
        Reset-PeriscopeBoundary
        $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('periscope-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Root | Out-Null
        $script:state = @{ gp = 0; downloads = 0; started = New-Object System.Collections.Generic.List[string] }
        Set-PeriscopeBoundary -Probe { $false } -Start {
            param($File, $WorkingDirectory)
            $script:state.started.Add([string]$File)
        } -Download {
            param($Url, $Sha, $Dest)
            $script:state.downloads++
            @{ ok = $false; code = 'NO_RELEASE'; message = 'test download should not run' }
        } -Gangplank {
            param($Repo, $Dest, $Token, $ModulePath, $UseStore)
            $script:state.gp++
            @{ ok = $false; code = 'GANGPLANK_DISABLED'; message = 'test gangplank should not run' }
        }
    }
    AfterEach {
        Reset-PeriscopeBoundary
        if ($script:Root -and (Test-Path $script:Root)) { Remove-Item $script:Root -Recurse -Force }
    }

    It 'starts a bat that is already in the Periscope folder and does not call Gangplank' {
        $tool = Get-CatTool 'halyard'
        $dir = Get-PeriscopeUtilityDir -AppData $script:Root -Id 'halyard'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'Launch-Halyard.bat') '@echo off'
        $off = [pscustomobject]@{ Configured = $false; Token = $null; UseStore = $false }
        $r = Invoke-PeriscopeLaunch -Tool $tool -AppData $script:Root -Credential $off
        $r.state | Should -Be 'launched'
        $script:state.started.Count | Should -Be 1
        $script:state.gp | Should -Be 0
        $script:state.downloads | Should -Be 0
    }

    It 'shows the install walkthrough when Gangplank is missing and no pin is recorded' {
        $off = [pscustomobject]@{ Configured = $false; Token = $null; UseStore = $false }
        $r = Invoke-PeriscopeLaunch -Tool (Get-CatTool 'halyard') -AppData $script:Root -Credential $off
        $r.state | Should -Be 'walkthrough'
        $r.step | Should -Be 'install'
        $r.message | Should -Match 'will not guess a download URL'
        $script:state.gp | Should -Be 0
        $script:state.downloads | Should -Be 0
        $script:state.started.Count | Should -Be 0
    }

    It 'points at the token step and does not re-download when Gangplank is present without a token' {
        $gdir = Get-PeriscopeUtilityDir -AppData $script:Root -Id 'gangplank'
        New-Item -ItemType Directory -Path $gdir | Out-Null
        Set-Content -LiteralPath (Join-Path $gdir 'Launch-Gangplank.bat') '@echo off'
        $off = [pscustomobject]@{ Configured = $false; Token = $null; UseStore = $false }
        $r = Invoke-PeriscopeLaunch -Tool (Get-CatTool 'capstan') -AppData $script:Root -Credential $off
        $r.state | Should -Be 'walkthrough'
        $r.step | Should -Be 'token'
        $r.message | Should -Match 'does not ask for a token'
        $script:state.downloads | Should -Be 0
        $script:state.gp | Should -Be 0
    }

    It 'refuses a folder that is not a Periscope download' {
        $dir = Get-PeriscopeUtilityDir -AppData $script:Root -Id 'halyard'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'notes.txt') 'keep me'
        $on = [pscustomobject]@{ Configured = $true; Token = 'test-token-not-secret'; UseStore = $false }
        Set-PeriscopeBoundary -Probe { $true }
        $r = Invoke-PeriscopeLaunch -Tool (Get-CatTool 'halyard') -AppData $script:Root -Credential $on
        $r.ok | Should -BeFalse
        $r.code | Should -Be 'FOLDER_EXISTS'
        $r.message | Should -Be 'Folder already exists, not a Periscope download'
        $script:state.gp | Should -Be 0
        Test-Path (Join-Path $dir 'notes.txt') | Should -BeTrue
    }

    It 'downloads through the Gangplank boundary, strips one zip root, then starts the root bat' {
        $on = [pscustomobject]@{ Configured = $true; Token = 'test-token-not-secret'; UseStore = $false }
        Set-PeriscopeBoundary -Probe { $true } -Gangplank {
            param($Repo, $Dest, $Token, $ModulePath, $UseStore)
            $script:state.gp++
            $nested = Join-Path $Dest 'Halyard-main'
            New-Item -ItemType Directory -Path $nested -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $nested 'Launch-Halyard.bat') '@echo off'
            @{ ok = $true; code = 'OK'; message = '' }
        }
        $r = Invoke-PeriscopeLaunch -Tool (Get-CatTool 'halyard') -AppData $script:Root -Credential $on
        $r.state | Should -Be 'launched'
        $script:state.gp | Should -Be 1
        $script:state.downloads | Should -Be 0
        $rootBat = Join-Path (Get-PeriscopeUtilityDir -AppData $script:Root -Id 'halyard') 'Launch-Halyard.bat'
        Test-Path -LiteralPath $rootBat | Should -BeTrue
        $script:state.started[$script:state.started.Count - 1] | Should -Be $rootBat
    }

    It 'reports a missing launcher after Gangplank returns and does not start anything' {
        $on = [pscustomobject]@{ Configured = $true; Token = 'test-token-not-secret'; UseStore = $false }
        Set-PeriscopeBoundary -Probe { $true } -Gangplank {
            param($Repo, $Dest, $Token, $ModulePath, $UseStore)
            $script:state.gp++
            if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest | Out-Null }
            Set-Content -LiteralPath (Join-Path $Dest 'README.md') 'no bat'
            @{ ok = $true; code = 'OK'; message = '' }
        }
        $r = Invoke-PeriscopeLaunch -Tool (Get-CatTool 'halyard') -AppData $script:Root -Credential $on
        $r.ok | Should -BeFalse
        $r.message | Should -Be 'Downloaded, but no launcher found for Halyard'
        $script:state.started.Count | Should -Be 0
    }

    It 'does not call the pinned download unless both a URL and a SHA are set' {
        (Invoke-PeriscopePinnedDownload -Url '' -Sha256 '' -Dest $script:Root).code | Should -Be 'NO_RELEASE'
        (Invoke-PeriscopePinnedDownload -Url 'https://example.invalid/gangplank.zip' -Sha256 'abcd' -Dest $script:Root).code | Should -Be 'NO_RELEASE'
        $off = [pscustomobject]@{ Configured = $false; Token = $null; UseStore = $false }
        $r = Invoke-PeriscopeLaunch -Tool (Get-CatTool 'halyard') -AppData $script:Root -Credential $off -ReleaseUrl 'https://example.invalid/gangplank.zip' -ReleaseSha256 ('ab' * 32)
        # The boundary, not the network, receives a fully pinned request. This mock refuses it.
        $r.code | Should -Be 'NO_RELEASE'
        $script:state.downloads | Should -Be 1
        $script:state.gp | Should -Be 0
    }
}

Describe 'zip root and static files' {
    It 'strips a single top-level zip folder so the bat lands at the download root' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $work = Join-Path ([IO.Path]::GetTempPath()) ('periscope-zip-' + [guid]::NewGuid().ToString('N'))
        $src = Join-Path $work 'src\ToolRoot'
        $zip = Join-Path $work 'tool.zip'
        $dest = Join-Path $work 'out'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'Launch-Halyard.bat') '@echo off'
        [IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $work 'src'), $zip)
        Expand-PeriscopeZip -Zip $zip -Dest $dest -BatName 'Launch-Halyard.bat' | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $dest 'Launch-Halyard.bat') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $dest 'ToolRoot') | Should -BeFalse
        Remove-Item $work -Recurse -Force
    }
    It 'injects the session token only into a served copy of index.html' {
        $indexPath = Join-Path $script:RepoRoot 'index.html'
        $raw = [IO.File]::ReadAllText($indexPath)
        $raw | Should -Not -Match 'periscope-token'
        $raw | Should -Match '<title>Periscope</title>'
        $raw | Should -Match '<h1>Periscope</h1>'
        $raw | Should -Match 'FleetHacker Edge-Ops utility suite'
        $served = Add-PeriscopeTokenMeta -Html $raw -Token ('ab' * 32)
        $served | Should -Match 'name="periscope-token" content="abab'
        [IO.File]::ReadAllText($indexPath) | Should -Not -Match 'periscope-token'
        Resolve-PeriscopeStatic -Root $script:RepoRoot -UrlPath '/assets/app.js' | Should -Not -BeNullOrEmpty
        Resolve-PeriscopeStatic -Root $script:RepoRoot -UrlPath '/../catalog.json' | Should -BeNullOrEmpty
        Resolve-PeriscopeStatic -Root $script:RepoRoot -UrlPath '/tools/periscope/Periscope.ps1' | Should -BeNullOrEmpty
    }
}

Describe 'local host request checks' {
    It 'accepts only 127.0.0.1 and localhost for the IPv4 loopback bind' {
        Test-PeriscopeLoopbackHost -HostHeader '127.0.0.1:8803' -Port 8803 | Should -BeTrue
        Test-PeriscopeLoopbackHost -HostHeader 'localhost:8803' -Port 8803 | Should -BeTrue
        Test-PeriscopeLoopbackHost -HostHeader 'LocalHost:8803' -Port 8803 | Should -BeTrue
        Test-PeriscopeLoopbackHost -HostHeader 'evil.example:8803' -Port 8803 | Should -BeFalse
        Test-PeriscopeLoopbackHost -HostHeader '127.0.0.1:8804' -Port 8803 | Should -BeFalse
        Test-PeriscopeLoopbackHost -HostHeader '' -Port 8803 | Should -BeFalse
    }
    It 'allows a missing, same-origin, or none Sec-Fetch-Site and rejects the rest' {
        Test-PeriscopeFetchSite -Headers @{} | Should -BeTrue
        Test-PeriscopeFetchSite -Headers @{ 'Sec-Fetch-Site' = 'same-origin' } | Should -BeTrue
        Test-PeriscopeFetchSite -Headers @{ 'Sec-Fetch-Site' = 'none' } | Should -BeTrue
        Test-PeriscopeFetchSite -Headers @{ 'Sec-Fetch-Site' = 'cross-site' } | Should -BeFalse
    }
    It 'checks Host on every response before the page token is added' {
        $hostPs1 = Get-Content -Raw (Join-Path $PSScriptRoot '..\Periscope.ps1')
        $tokenAt = $hostPs1.IndexOf('Add-PeriscopeTokenMeta')
        $hostAt = $hostPs1.IndexOf('Test-PeriscopeLoopbackHost')
        $hostAt | Should -BeGreaterThan 0
        $tokenAt | Should -BeGreaterThan $hostAt
        $hostPs1 | Should -Match 'IPv4 loopback only'
        $hostPs1 | Should -Match 'X-Content-Type-Options'
        $hostPs1 | Should -Match "frame-ancestors 'none'"
    }
}

Describe 'Gangplank child environment' {
    It 'drops GANGPLANK_TOKEN and keeps the variables the child needs' {
        $src = @{
            SystemRoot = 'C:\Windows'
            GANGPLANK_TOKEN = 'should-not-pass'
            PATH = 'C:\Windows'
            LOCALAPPDATA = 'C:\Users\me\AppData\Local'
        }
        $clean = Get-PeriscopeChildEnvironment -Source $src
        $clean.ContainsKey('GANGPLANK_TOKEN') | Should -BeFalse
        $clean['SystemRoot'] | Should -Be 'C:\Windows'
        $clean['LOCALAPPDATA'] | Should -Be 'C:\Users\me\AppData\Local'
        $clean['PATH'] | Should -Be 'C:\Windows'
    }
    It 'writes the DPAPI file under LOCALAPPDATA with CreateNew and scrubs the child environment' {
        $module = Get-Content -Raw (Join-Path $PSScriptRoot '..\Periscope.psm1')
        $module | Should -Match 'Periscope\\tokens'
        $module | Should -Match '\[IO\.FileMode\]::CreateNew'
        $module | Should -Match 'Get-PeriscopeChildEnvironment'
        $module | Should -Match 'EnvironmentVariables\.Clear\(\)'
        $module | Should -Not -Match 'GetTempPath\(\).*token'
    }
}

Describe 'Gangplank stays out of process' {
    It 'does not import Gangplank in the host module and does not fetch a utility zip from the child' {
        $module = Get-Content -Raw (Join-Path $PSScriptRoot '..\Periscope.psm1')
        $child = Get-Content -Raw (Join-Path $PSScriptRoot '..\Invoke-GangplankChild.ps1')
        $module | Should -Not -Match 'Import-Module[^\r\n]*Gangplank'
        $child | Should -Match 'Import-Module -LiteralPath'
        $child | Should -Not -Match 'Invoke-WebRequest'
        $child | Should -Not -Match 'raw\.githubusercontent'
        $child | Should -Match 'ProtectedData'
        $child | Should -Match 'Remove-Item -LiteralPath \$tokenFile'
    }
}
