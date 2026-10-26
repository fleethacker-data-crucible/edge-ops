# Pester 5. Runs on Windows PowerShell 5.1 and pwsh.
# Build-Site.ps1 must build under Set-StrictMode -Version 2 when optional catalog properties are missing.
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildScript = Join-Path $RepoRoot 'scripts\Build-Site.ps1'

    function New-TestRoot([object[]]$Tools) {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('edgeops-build-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        foreach ($item in @('index.html', 'assets', 'templates', 'ui-kit')) {
            Copy-Item (Join-Path $RepoRoot $item) (Join-Path $root $item) -Recurse
        }
        $catalog = Get-Content -Raw (Join-Path $RepoRoot 'catalog.json') | ConvertFrom-Json
        $catalog.tools = $Tools
        $json = $catalog | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText((Join-Path $root 'catalog.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
        return $root
    }
}

Describe 'Build-Site.ps1 optional catalog properties (StrictMode 2)' {
    BeforeAll {
        Set-StrictMode -Version 2
        # Needs installs, and has no installNote, defaultPort, external, externalSource or releases property.
        $bare = [pscustomobject]@{
            id = 'bare-tool'; name = 'Bare Tool'; category = 'support'; summary = 'Test entry.'
            launcher = 'Launch-Bare.bat'; status = 'prototype'; repo = 'https://example.invalid/bare'
            requirements = [pscustomobject]@{ installs = $true }
        }
        # No launcher property and an empty requirements object.
        $nolaunch = [pscustomobject]@{
            id = 'no-launch'; name = 'No Launch'; category = 'support'; summary = 'Test entry.'
            status = 'sandbox'; repo = 'https://example.invalid/none'; requirements = [pscustomobject]@{}
        }
        # A launcher and no installs, but no defaultPort property.
        $plain = [pscustomobject]@{
            id = 'plain'; name = 'Plain'; category = 'support'; summary = 'Test entry.'; launcher = 'Launch-Plain.bat'
            status = 'prototype'; repo = 'https://example.invalid/plain'; requirements = [pscustomobject]@{ ps51 = $true }
        }
        $script:Root = New-TestRoot @($bare, $nolaunch, $plain)
        & $BuildScript -Root $Root -OutDir '_site' | Out-Null
        $script:BareHtml = [System.IO.File]::ReadAllText((Join-Path $Root '_site\tools\bare-tool.html'))
        $script:PlainHtml = [System.IO.File]::ReadAllText((Join-Path $Root '_site\tools\plain.html'))
        $script:NoLaunchHtml = [System.IO.File]::ReadAllText((Join-Path $Root '_site\tools\no-launch.html'))
    }
    AfterAll {
        Set-StrictMode -Off
        if ($Root -and (Test-Path $Root)) { Remove-Item $Root -Recurse -Force }
    }

    It 'shows the fallback install text when installNote is missing' {
        $BareHtml | Should -Match 'Needs third-party installs; see the repo README\.'
        $BareHtml | Should -Not -Match 'Run on whitelisted Windows'
    }
    It 'treats a missing defaultPort as no local server' {
        $PlainHtml | Should -Match 'No local server needed\.'
        $PlainHtml | Should -Not -Match 'badge grey">(free port|port )'
    }
    It 'omits the external note when external is missing' {
        $BareHtml | Should -Not -Match 'External source'
    }
    It 'replaces the run steps when launcher is missing' {
        $NoLaunchHtml | Should -Match 'Nothing to launch yet\.'
    }
}

Describe 'Build-Site.ps1 installNote present' {
    BeforeAll {
        Set-StrictMode -Version 2
        $t = [pscustomobject]@{
            id = 'noted'; name = 'Noted'; category = 'support'; summary = 'Test entry.'; launcher = 'x.bat'
            defaultPort = 8773; status = 'prototype'; repo = 'https://example.invalid/n'; releases = $null
            external = $false; installNote = 'Needs Python 3.12 and pip install.'
            requirements = [pscustomobject]@{ installs = $true }
        }
        $script:Root2 = New-TestRoot @($t)
        & $BuildScript -Root $Root2 -OutDir '_site' | Out-Null
        $script:Html = [System.IO.File]::ReadAllText((Join-Path $Root2 '_site\tools\noted.html'))
    }
    AfterAll {
        Set-StrictMode -Off
        if ($Root2 -and (Test-Path $Root2)) { Remove-Item $Root2 -Recurse -Force }
    }
    It 'uses the catalog installNote' {
        $Html | Should -Match 'Needs Python 3\.12 and pip install\.'
    }
}
