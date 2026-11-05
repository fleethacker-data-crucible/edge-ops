# Pester 5. Runs on Windows PowerShell 5.1 and pwsh. Hand checks for the hub page: the catalog and its file:// fallback
# agree, every tool has an emblem, the Bridge Warden entry, the SCOPE skin wiring, and the wording rule for the page
# (nothing on the hub may claim a status or capability: no "authorized", "accredited", "approved" or "ATO").
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Cat = Get-Content -Raw (Join-Path $RepoRoot 'catalog.json') | ConvertFrom-Json
    $js = Get-Content -Raw (Join-Path $RepoRoot 'assets\catalog-data.js')
    $script:Fallback = ($js -replace '(?s)^.*?window\.EDGE_OPS_CATALOG\s*=\s*', '' -replace ';\s*$', '') | ConvertFrom-Json
    $script:Index = Get-Content -Raw (Join-Path $RepoRoot 'index.html')
    $script:Skin = Get-Content -Raw (Join-Path $RepoRoot 'assets\brand-scope.js')
    $script:App = Get-Content -Raw (Join-Path $RepoRoot 'assets\app.js')
    $script:Claim = '(?i)\b(authori[sz]ed|accredited|approved|ATO)\b'
}

Describe 'catalog.json and its file:// fallback' {
    It 'hold the same data' {
        ($Fallback | ConvertTo-Json -Depth 10 -Compress) | Should -Be ($Cat | ConvertTo-Json -Depth 10 -Compress)
    }
    It 'give every tool an emblem in assets/emblems' {
        foreach ($t in $Cat.tools) {
            Test-Path -LiteralPath (Join-Path $RepoRoot ('assets\emblems\' + $t.id + '.svg')) | Should -BeTrue -Because "$($t.id) should have an emblem"
        }
    }
}

Describe 'Bridge Warden catalog entry' {
    BeforeAll { $script:Bw = $Cat.tools | Where-Object { $_.id -eq 'bridge-warden' } }
    It 'is in the Local AI platform group, unreleased, on the provisional port 8774' {
        $Bw | Should -Not -BeNullOrEmpty
        $Bw.group | Should -Be 'local-ai'
        $Bw.status | Should -Be 'unreleased'
        $Bw.defaultPort | Should -Be 8774
        $Bw.portNote | Should -Match 'provisional'
        $Bw.portNote | Should -Match 'Eight-Bells'
    }
    It 'claims no status in its wording' {
        ($Bw.summary + ' ' + $Bw.portNote) | Should -Not -Match $Claim
    }
}

Describe 'SCOPE skin' {
    It 'is the default hub and is loaded by index.html after theme.js' {
        $Index | Should -Match 'data-brand="scope"'
        $Index | Should -Match 'assets/brand-scope\.css'
        $Index | Should -Match '(?s)<script src="assets/theme\.js"></script>\s*<script src="assets/brand-scope\.js"></script>'
        $Skin | Should -Match "q === 'edgeops'"
        $Skin | Should -Match "get\(KEY\) === 'edgeops'"
        $Skin | Should -Not -Match 'theme\.set\(SCOPE_THEME\)'
    }
    It 'keeps the expansion in one constant whose initials spell SCOPE' {
        $m = [regex]::Match($Skin, "var SCOPE_EXPANSION = '([^']+)'")
        $m.Success | Should -BeTrue
        $initials = -join ($m.Groups[1].Value.Split(' ') | ForEach-Object { $_.Substring(0, 1) })
        $initials | Should -Be 'SCOPE'
    }
    It 'has its emblem and its stylesheet' {
        Test-Path -LiteralPath (Join-Path $RepoRoot 'assets\emblems\scope.svg') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $RepoRoot 'assets\brand-scope.css') | Should -BeTrue
        $Skin | Should -Match "SCOPE_CSS = 'assets/brand-scope.css'"
    }
    It 'keeps brass to hairlines: only the wordmark rule and focus rings use it' {
        $css = Get-Content -Raw (Join-Path $RepoRoot 'assets\brand-scope.css')
        $css | Should -Match ':root\[data-brand=scope\]\{[^}]*--scope-accent:#[0-9a-f]{6}' -Because 'the Night watch accent is declared on :root[data-brand=scope]'
        $css | Should -Match ':root\.light\[data-brand=scope\]\{[^}]*--scope-accent:#[0-9a-f]{6}' -Because 'the Chart room accent is declared under the .light class theme.js sets'
        $uses = @(($css -split '\r?\n') | Where-Object { $_ -like '*var(--scope-brass)*' })
        @($uses).Count | Should -BeGreaterThan 0
        foreach ($line in $uses) { ($line -match 'scope-rule|focus|^:root') | Should -BeTrue -Because "brass is a hairline only, not: $line" }
    }
    It 'claims no status anywhere on the page' {
        foreach ($text in @($Index, $Skin, $App)) { $text | Should -Not -Match $Claim }
    }
}

Describe 'primary catalog rows' {
    It 'leads with the four screenshot rows and keeps voice, secrets and support visible' {
        $ids = @($Cat.groups | ForEach-Object { $_.id })
        ($ids[0..3] -join ',') | Should -Be 'capture-media-files,work-collaboration,data-analytics,local-ai'
        foreach ($extra in @('voice-learning', 'secrets-security', 'support')) {
            $ids | Should -Contain $extra
            @($Cat.tools | Where-Object { $_.group -eq $extra }).Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'default theme' {
    It 'is Fleet Night watch, and the switcher still lists every theme' {
        $themeJs = Get-Content -Raw (Join-Path $RepoRoot 'assets\theme.js')
        $themeJs | Should -Match "DEFAULT_PREF = 'fleet-night-watch'"
        $themeJs | Should -Match "dark: 'fleet-night-watch'"
        $themeJs | Should -Match "light: 'phoenix-light'"
        foreach ($id in @('phoenix-dark', 'phoenix-light', 'fleet-night-watch', 'fleet-chart-room', 'System default')) {
            $themeJs | Should -Match ([regex]::Escape($id))
        }
    }
}

Describe 'Demo button' {
    It 'opens in a new tab and says what it does' {
        $App | Should -Match "el\('a','btn demo','Demo'\)"
        $App | Should -Match "target='_blank'"
        $App | Should -Match "rel='noopener'"
        $App | Should -Match 'this button does not start it'
    }
    It 'prefers a commissioning video on hosted pages and loopback from file://' {
        $App | Should -Match 'demoVideo'
        $App | Should -Match 'demoPage'
        $App | Should -Match "location.protocol==='file:'"
        $App | Should -Match 'https:\\/\\/'
        $App | Should -Match 'http://127.0.0.1:'
        $App | Should -Match 'if\(file&&port\)return port;if\(video\)return video;if\(port\)return port;'
        $App | Should -Match 'isPages\(dv\)'
        $App | Should -Match 'raw\.githubusercontent'
        $App | Should -Match 'if\(dv&&isPages\(dv\)\)return dv;'
    }
    It 'does not vendor commissioning videos, and only https demo links would count' {
        $media = @(Get-ChildItem -Path $RepoRoot -Recurse -File -Include *.mp4, *.webm, *.mov -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/]_site[\\/]' -and $_.FullName -notmatch '[\\/]\.git[\\/]' })
        $media.Count | Should -Be 0
        foreach ($t in $Cat.tools) {
            foreach ($field in @('demoVideo', 'demoPage')) {
                $v = $t.PSObject.Properties[$field]
                if ($null -ne $v -and $v.Value) { [string]$v.Value | Should -Match '^https://\S+$' }
            }
        }
    }
}

Describe 'Periscope display and Launch button' {
    It 'titles the page Periscope and keeps the suite subtitle' {
        $Index | Should -Match '<title>Periscope</title>'
        $Index | Should -Match '<h1>Periscope</h1>'
        $Index | Should -Match 'FleetHacker Edge-Ops utility suite'
        $Skin | Should -Match "SCOPE_PAGE_TITLE = 'Periscope'"
    }
    It 'does not show Launch until the local host status call succeeds' {
        $Index | Should -Not -Match 'periscope-token'
        $Index | Should -Not -Match '>Launch<'
        $App | Should -Match 'api/periscope/status'
        $App | Should -Match 'body\.ok===true'
        $App | Should -Match "aria-label','Launch '"
        $App | Should -Match 'g\.support'
        $App | Should -Match 'periscopeLocal'
    }
}
