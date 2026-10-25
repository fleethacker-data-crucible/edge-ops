# Pester 5 scaffold. Copy to <repo>/tests/ next to your copy of LoopbackPort.ps1 (or adjust the path).
# Run: Invoke-Pester -Path .\tests -Output Detailed
BeforeAll {
    $script:SnippetPath = Join-Path $PSScriptRoot '..\ports\LoopbackPort.ps1'
    if (-not (Test-Path $script:SnippetPath)) { $script:SnippetPath = Join-Path $PSScriptRoot '..\LoopbackPort.ps1' }
    . $script:SnippetPath
}

Describe 'Start-LoopbackListener' {
    It 'binds to 127.0.0.1 only' {
        $l = Start-LoopbackListener -PreferredPort 8771 -RangeStart 8771 -RangeEnd 8779
        try {
            Get-ListenerHost -Listener $l | Should -Be '127.0.0.1'
            @($l.Prefixes).Count | Should -Be 1
        } finally { $l.Close() }
    }

    It 'falls back to the next port in the range when the preferred port is taken' {
        $first = Start-LoopbackListener -PreferredPort 8771 -RangeStart 8771 -RangeEnd 8779
        try {
            $taken = Get-ListenerPort -Listener $first
            $second = Start-LoopbackListener -PreferredPort $taken -RangeStart 8771 -RangeEnd 8779
            try {
                Get-ListenerPort -Listener $second | Should -Not -Be $taken
                Get-ListenerHost -Listener $second | Should -Be '127.0.0.1'
            } finally { $second.Close() }
        } finally { $first.Close() }
    }

    It 'rejects ports below 1024' {
        { Start-LoopbackListener -PreferredPort 80 } | Should -Throw
    }
}

Describe 'PowerShell 5.1 rules' {
    It 'repository scripts pass PSScriptAnalyzer with the shared settings' -Skip:(-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
        $root = Join-Path $PSScriptRoot '..'
        $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
        if (-not (Test-Path $settings)) { $settings = Join-Path $root '..\PSScriptAnalyzerSettings.psd1' }
        $found = Invoke-ScriptAnalyzer -Path $root -Recurse -Settings $settings -Severity Error |
            Where-Object { -not ($_.ScriptName -like '*.Tests.ps1' -and $_.RuleName -eq 'PSUseCompatibleCommands') }
        @($found).Count | Should -Be 0
    }
}
