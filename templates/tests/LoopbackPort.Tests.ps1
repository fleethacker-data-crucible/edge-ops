# Pester 5 scaffold. Copy to <repo>/tests/ next to your copy of LoopbackPort.ps1 (or adjust the path).
# Run: Invoke-Pester -Path .\tests -Output Detailed
BeforeAll {
    $script:SnippetPath = Join-Path $PSScriptRoot '..\ports\LoopbackPort.ps1'
    if (-not (Test-Path $script:SnippetPath)) { $script:SnippetPath = Join-Path $PSScriptRoot '..\LoopbackPort.ps1' }
    . $script:SnippetPath
}

Describe 'Start-LoopbackListener' {
    It 'binds to localhost only (one loopback prefix)' {
        $l = Start-LoopbackListener -PreferredPort 8771 -RangeStart 8771 -RangeEnd 8779
        try {
            Get-ListenerHost -Listener $l | Should -Be 'localhost'
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
                Get-ListenerHost -Listener $second | Should -Be 'localhost'
            } finally { $second.Close() }
        } finally { $first.Close() }
    }

    It 'treats a port held on IPv4 loopback as busy' {
        $b = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), 0
        $b.Start()
        try { Test-LoopbackPortFree -Port ([System.Net.IPEndPoint]$b.LocalEndpoint).Port | Should -BeFalse } finally { $b.Stop() }
    }

    It 'treats a port held on IPv6 loopback as busy' {
        $b = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::IPv6Loopback), 0
        try { $b.Start() } catch { Set-ItResult -Skipped -Because 'IPv6 loopback not available'; return }
        try { Test-LoopbackPortFree -Port ([System.Net.IPEndPoint]$b.LocalEndpoint).Port | Should -BeFalse } finally { $b.Stop() }
    }

    It 'rejects ports below 1024' {
        { Start-LoopbackListener -PreferredPort 80 } | Should -Throw
    }
}

Describe 'Bind rule guard' {
    It 'rejects wildcard or non-loopback prefix <Prefix>' -TestCases @(
        @{ Prefix = 'http://+:8771/' }, @{ Prefix = 'http://*:8771/' }, @{ Prefix = 'http://0.0.0.0:8771/' },
        @{ Prefix = 'http://[::]:8771/' }, @{ Prefix = 'http://192.168.1.10:8771/' }, @{ Prefix = 'http://myhost:8771/' }
    ) {
        { Assert-LoopbackPrefix -Prefix $Prefix } | Should -Throw -ExpectedMessage '*Bind rule*'
    }
    It 'accepts loopback prefix <Prefix>' -TestCases @(
        @{ Prefix = 'http://localhost:8771/' }, @{ Prefix = 'http://127.0.0.1:8771/' }, @{ Prefix = 'http://[::1]:8771/' }
    ) {
        { Assert-LoopbackPrefix -Prefix $Prefix } | Should -Not -Throw
    }
    It 'Start-LoopbackListener refuses -ListenHost <H> before binding' -TestCases @(
        @{ H = '+' }, @{ H = '*' }, @{ H = '0.0.0.0' }
    ) {
        { Start-LoopbackListener -PreferredPort 8771 -RangeStart 8771 -RangeEnd 8771 -ListenHost $H } | Should -Throw -ExpectedMessage '*Bind rule*'
    }
    It 'throws the bind-rule error for a bad host even when every port is busy' {
        $hold = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), 8775
        $hold.Start()
        try {
            { Start-LoopbackListener -PreferredPort 8775 -RangeStart 8775 -RangeEnd 8775 -ListenHost '+' } | Should -Throw -ExpectedMessage '*Bind rule*'
        } finally { $hold.Stop() }
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
