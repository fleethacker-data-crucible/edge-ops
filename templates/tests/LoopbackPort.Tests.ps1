# Pester 5 scaffold. Copy to <repo>/tests/ and point $script:SnippetPath at your copy.
# Run: Invoke-Pester -Path .\tests -Output Detailed
BeforeAll {
    Set-StrictMode -Version 2.0
    $script:SnippetPath = Join-Path $PSScriptRoot '..\ports\LoopbackPort.ps1'
    if (-not (Test-Path $script:SnippetPath)) { $script:SnippetPath = Join-Path $PSScriptRoot '..\LoopbackPort.ps1' }
    . $script:SnippetPath
}

Describe 'New-LoopbackListener' {
    It 'binds to 127.0.0.1 only' {
        $l = New-LoopbackListener -PreferredPort 8771
        try {
            Get-ListenerAddress -Listener $l | Should -Be '127.0.0.1'
        } finally { $l.Stop() }
    }

    It 'falls back to a different free port when the preferred port is taken' {
        $blocker = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), 0
        $blocker.Start()
        try {
            $taken = ([System.Net.IPEndPoint]$blocker.LocalEndpoint).Port
            if ($taken -lt 1024) { Set-ItResult -Skipped -Because 'OS gave a port below 1024' ; return }
            $l = New-LoopbackListener -PreferredPort $taken
            try {
                Get-ListenerPort -Listener $l | Should -Not -Be $taken
                Get-ListenerAddress -Listener $l | Should -Be '127.0.0.1'
            } finally { $l.Stop() }
        } finally { $blocker.Stop() }
    }

    It 'rejects ports below 1024' {
        { New-LoopbackListener -PreferredPort 80 } | Should -Throw
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
