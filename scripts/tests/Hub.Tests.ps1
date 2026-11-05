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
    It 'is loaded by index.html after theme.js' {
        $Index | Should -Match '(?s)<script src="assets/theme\.js"></script>\s*<script src="assets/brand-scope\.js"></script>'
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
        $css | Should -Match '--accent:var\(--scope-accent\)'
        $uses = [regex]::Matches($css, '(?m)^[^\r\n]*var\(--scope-brass\)[^\r\n]*$') | ForEach-Object { $_.Value }
        @($uses).Count | Should -BeGreaterThan 0
        foreach ($line in $uses) { ($line -match 'scope-rule|focus') | Should -BeTrue -Because "brass is a hairline only, not: $line" }
    }
    It 'claims no status anywhere on the page' {
        foreach ($text in @($Index, $Skin, $App)) { $text | Should -Not -Match $Claim }
    }
}

Describe 'Demo button' {
    It 'opens in a new tab and says what it does' {
        $App | Should -Match "el\('a','btn demo','Demo'\)"
        $App | Should -Match "target='_blank'"
        $App | Should -Match "rel='noopener'"
        $App | Should -Match 'this button does not start it'
    }
}
