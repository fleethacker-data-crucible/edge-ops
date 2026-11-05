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

Describe 'Build-Site.ps1 automation (CLI and API for agents)' {
    BeforeAll {
        Set-StrictMode -Version 2
        $agent = [pscustomobject]@{
            id = 'agent'; name = 'Agent'; category = 'data-ai'; summary = 'Test entry.'; launcher = 'Launch-Agent.bat'
            status = 'prototype'; repo = 'https://example.invalid/a'; requirements = [pscustomobject]@{ ps51 = $true }
            automation = [pscustomobject]@{ cli = $true; json = $true; api = 'openai-v1'; mcp = $false; describe = 'Launch-Agent.bat commands --json' }
        }
        # No automation property at all (most tools today).
        $silent = [pscustomobject]@{
            id = 'silent'; name = 'Silent'; category = 'support'; summary = 'Test entry.'; launcher = 'Launch-Silent.bat'
            status = 'prototype'; repo = 'https://example.invalid/s'; requirements = [pscustomobject]@{ ps51 = $true }
        }
        $script:Root3 = New-TestRoot @($agent, $silent)
        & $BuildScript -Root $Root3 -OutDir '_site' | Out-Null
        $script:AgentHtml = [System.IO.File]::ReadAllText((Join-Path $Root3 '_site\tools\agent.html'))
        $script:SilentHtml = [System.IO.File]::ReadAllText((Join-Path $Root3 '_site\tools\silent.html'))
    }
    AfterAll {
        Set-StrictMode -Off
        if ($Root3 -and (Test-Path $Root3)) { Remove-Item $Root3 -Recurse -Force }
    }
    It 'shows a For agents table from the catalog' {
        $AgentHtml | Should -Match '<h2>For agents</h2>'
        $AgentHtml | Should -Match 'OpenAI-compatible <code>/v1</code>'
        $AgentHtml | Should -Match '<code>Launch-Agent\.bat commands --json</code>'
        $AgentHtml | Should -Match 'MCP server</td><td>No'
    }
    It 'adds nothing when the catalog records no automation' {
        $SilentHtml | Should -Not -Match 'For agents'
        $SilentHtml | Should -Not -Match '\{\{AUTOMATION\}\}'
    }
}

Describe 'catalog.json functional groups (hub grouping, one source of truth)' {
    BeforeAll {
        $script:Cat = Get-Content -Raw (Join-Path $RepoRoot 'catalog.json') | ConvertFrom-Json
        $js = Get-Content -Raw (Join-Path $RepoRoot 'assets\catalog-data.js')
        $script:Fallback = ($js -replace '(?s)^.*?window\.EDGE_OPS_CATALOG\s*=\s*', '' -replace ';\s*$', '') | ConvertFrom-Json
        $script:GroupIds = @($Cat.groups | ForEach-Object { $_.id })
    }
    It 'defines each group once, with a name' {
        $GroupIds.Count | Should -BeGreaterThan 0
        @($GroupIds | Select-Object -Unique).Count | Should -Be $GroupIds.Count
        @($Cat.groups | Where-Object { -not $_.name }).Count | Should -Be 0
    }
    It 'puts every tool in exactly one defined group' {
        foreach ($t in $Cat.tools) { $GroupIds | Should -Contain $t.group }
    }
    It 'leaves no group empty' {
        foreach ($g in $GroupIds) { @($Cat.tools | Where-Object { $_.group -eq $g }).Count | Should -BeGreaterThan 0 }
    }
    It 'marks Halyard Ballast as a support repo, not a user tool' {
        $ballast = $Cat.tools | Where-Object { $_.id -eq 'halyard-ballast' }
        $ballast.group | Should -Be 'support'
        ($Cat.groups | Where-Object { $_.id -eq 'support' }).support | Should -Be $true
        $ballast.repo | Should -Match 'Halyard-Ballast$'
    }
    It 'keeps assets/catalog-data.js in step with catalog.json' {
        ($Fallback | ConvertTo-Json -Depth 10 -Compress) | Should -Be ($Cat | ConvertTo-Json -Depth 10 -Compress)
    }
}

Describe 'Build-Site.ps1 offline catalog fallback' {
    BeforeAll {
        Set-StrictMode -Version 2
        $sync = [pscustomobject]@{
            id = 'sync'; name = 'Sync'; category = 'support'; group = 'support'; summary = 'Test entry.'
            status = 'sandbox'; repo = 'https://example.invalid/sync'; requirements = [pscustomobject]@{}
            demoVideo = 'https://example.invalid/commissioning/sync.mp4'
            demoPage = 'https://example.invalid/commissioning/sync.html'
        }
        $script:Root4 = New-TestRoot @($sync)
        & $BuildScript -Root $Root4 -OutDir '_site' | Out-Null
        $js = Get-Content -Raw (Join-Path $Root4 'assets\catalog-data.js')
        $script:Fb4 = ($js -replace '(?s)^.*?window\.EDGE_OPS_CATALOG\s*=\s*', '' -replace ';\s*$', '') | ConvertFrom-Json
        $script:Cat4 = Get-Content -Raw (Join-Path $Root4 'catalog.json') | ConvertFrom-Json
        $script:SiteJs = Get-Content -Raw (Join-Path $Root4 '_site\assets\catalog-data.js')
        $script:SrcJs = $js
    }
    AfterAll {
        Set-StrictMode -Off
        if ($Root4 -and (Test-Path $Root4)) { Remove-Item $Root4 -Recurse -Force }
    }
    It 'rewrites assets/catalog-data.js from catalog.json, including demo links' {
        ($Fb4 | ConvertTo-Json -Depth 10 -Compress) | Should -Be ($Cat4 | ConvertTo-Json -Depth 10 -Compress)
        $tool = @($Fb4.tools) | Where-Object { $_.id -eq 'sync' }
        $tool.demoVideo | Should -Be 'https://example.invalid/commissioning/sync.mp4'
        $tool.demoPage | Should -Be 'https://example.invalid/commissioning/sync.html'
    }
    It 'ships that same fallback in _site' {
        $SiteJs | Should -Be $SrcJs
    }
}
