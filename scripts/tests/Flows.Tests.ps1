# Pester 5. Runs on Windows PowerShell 5.1 and pwsh. Hand checks for docs/FLOWS.md, the voice section of CONVENTIONS.md
# and the Semaphore catalog entry (edge-ops issue 37).
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Flows = Get-Content -Raw (Join-Path $RepoRoot 'docs\FLOWS.md')
    $script:Conv = Get-Content -Raw (Join-Path $RepoRoot 'CONVENTIONS.md')
    $script:Cat = Get-Content -Raw (Join-Path $RepoRoot 'catalog.json') | ConvertFrom-Json
    $js = Get-Content -Raw (Join-Path $RepoRoot 'assets\catalog-data.js')
    $script:Fallback = ($js -replace '(?s)^.*?window\.EDGE_OPS_CATALOG\s*=\s*', '' -replace ';\s*$', '') | ConvertFrom-Json
}

Describe 'docs/FLOWS.md hand-off file formats' {
    It 'names every hand-off format and its owning document' {
        foreach ($needle in @('snapshackle.capture/1', '.png.meta.json', 'CAPTURE-FORMAT.md', 'PROJECT-FILE.md', 'project.schema.json',
                'packetrat.usage-counts/1', 'counts.json', 'COUNTS-EXPORT.md', 'SEMAPHORE-EXPORT.md', 'synapse-peer-card', 'PEER-CARD-CONTRACT.md')) {
            $Flows.Contains($needle) | Should -BeTrue -Because "FLOWS.md should mention $needle"
        }
    }
    It 'covers the Capstan cursor data lists' {
        foreach ($needle in @('samples', 'clicks', 'keys')) { $Flows.Contains('`' + $needle + '`') | Should -BeTrue }
    }
    It 'has working relative links' {
        $docs = Join-Path $RepoRoot 'docs'
        foreach ($m in [regex]::Matches($Flows, '\]\((?!https?:)([^)#]+)(#[^)]*)?\)')) {
            Test-Path -LiteralPath (Join-Path $docs $m.Groups[1].Value) | Should -BeTrue -Because "link $($m.Groups[1].Value) should resolve"
        }
    }
}

Describe 'CONVENTIONS.md voice section' {
    It 'has a Voice section that points at the TalkForge contract and the Fairlead routes' {
        $Conv | Should -Match '(?m)^## Voice \(speech out and in\)'
        foreach ($needle in @('VOICE-CONTRACT.md', '/v1/audio/speech', '/v1/audio/transcriptions', '127.0.0.1:8776', 'Lazarette')) {
            $Conv.Contains($needle) | Should -BeTrue -Because "the voice section should mention $needle"
        }
    }
}

Describe 'Semaphore catalog entry' {
    BeforeAll { $script:Sem = $Cat.tools | Where-Object { $_.id -eq 'semaphore' } }
    It 'uses the 8800-8802 block and has a launcher' {
        $Sem.defaultPort | Should -BeGreaterOrEqual 8800
        $Sem.defaultPort | Should -BeLessOrEqual 8802
        $Sem.launcher | Should -Be 'Launch-Semaphore.bat'
        $Sem.summary | Should -Not -Match 'no UI yet'
    }
    It 'matches the offline fallback' {
        $fb = $Fallback.tools | Where-Object { $_.id -eq 'semaphore' }
        ($fb | ConvertTo-Json -Depth 10 -Compress) | Should -Be ($Sem | ConvertTo-Json -Depth 10 -Compress)
    }
}
