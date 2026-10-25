# Pester 5. Runs on Windows PowerShell 5.1 and pwsh. Ports 8835-8859 are used as scratch blocks.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FleetPort.psm1') -Force

    # A fake FleetHacker tool: HttpListener on localhost:<port> answering /__fleethacker/id and /shutdown.
    function Start-FakeTool([int]$Port, [string]$Tool, [string]$Version) {
        $mod = (Get-Module FleetPort).Path
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($mod, $port, $tool, $version)
            Import-Module $mod
            $l = New-Object System.Net.HttpListener
            $l.Prefixes.Add("http://localhost:$port/")
            $l.Start()
            try {
                while ($l.IsListening) {
                    $ctx = $l.GetContext()
                    $h = Invoke-FleetIdEndpoint -Context $ctx -Tool $tool -Version $version -Path 'fake-tool.ps1'
                    if ($h -eq 'shutdown') { break }
                    if (-not $h) { $ctx.Response.StatusCode = 200; $ctx.Response.Close() }
                }
            } finally { $l.Stop(); $l.Close() }
        }).AddArgument($mod).AddArgument($Port).AddArgument($Tool).AddArgument($Version)
        $h = $ps.BeginInvoke()
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ((Test-FleetPortFree -Port $Port) -and $sw.ElapsedMilliseconds -lt 5000) { Start-Sleep -Milliseconds 50 }
        return @{ PS = $ps; Handle = $h; Port = $Port }
    }
    function Stop-FakeTool($f) {
        if (-not $f) { return }
        if (-not (Test-FleetPortFree -Port $f.Port)) {
            try { $r = [Net.HttpWebRequest]::Create("http://localhost:$($f.Port)/__fleethacker/shutdown"); $r.Method = 'POST'; $r.Proxy = $null; $r.ContentLength = 0; $r.Headers['X-FleetHacker-Shutdown'] = '1'; $r.Timeout = 2000; $r.GetResponse().Close() } catch { }
        }
        [void]$f.Handle.AsyncWaitHandle.WaitOne(3000)
        $f.PS.Dispose()
    }
    # A foreign program: a raw TCP listener that never speaks HTTP.
    function Start-Foreign([int]$Port) {
        $t = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), $Port
        $t.Start(); return $t
    }
    $script:common = @{ Tool = 'demo'; Size = 3; ProbeTimeoutMs = 700; GraceMs = 3000 }
}

Describe 'Resolve-FleetPort' {
    AfterEach { if ($script:r -and $script:r.Listener) { $script:r.Listener.Close() }; $script:r = $null }

    It 'starts on the first port when it is free' {
        $script:r = Resolve-FleetPort @common -Version '1.0' -Start 8840 -Policy reuse
        $r.Action | Should -Be 'Start'
        $r.Port | Should -Be 8840
        $r.Listener.IsListening | Should -BeTrue
        @($r.Listener.Prefixes)[0] | Should -Be 'http://localhost:8840/'
    }

    It 'skips a port held by a foreign program and moves up inside the block' {
        $f = Start-Foreign 8843
        try {
            $script:r = Resolve-FleetPort @common -Version '1.0' -Start 8843 -Policy reuse
            $r.Action | Should -Be 'Start'
            $r.Port | Should -Be 8844
        } finally { $f.Stop() }
    }

    It 'reuses a running instance of the same tool and version' {
        $t = Start-FakeTool 8846 'demo' '1.0'
        try {
            $script:r = Resolve-FleetPort @common -Version '1.0' -Start 8846 -Policy reuse
            $r.Action | Should -Be 'Reuse'
            $r.Port | Should -Be 8846
            $r.Url | Should -Be 'http://localhost:8846/'
            $r.Existing.Version | Should -Be '1.0'
        } finally { Stop-FakeTool $t }
    }

    It 'stops an older version of itself gracefully and takes its port' {
        $t = Start-FakeTool 8849 'demo' '0.9'
        try {
            $script:r = Resolve-FleetPort @common -Version '1.0' -Start 8849 -Policy reuse
            $r.Action | Should -Be 'Start'
            $r.Port | Should -Be 8849
        } finally { Stop-FakeTool $t }
    }

    It 'reuses a NEWER running copy instead of downgrading it, and notes the stale launcher' {
        $t = Start-FakeTool 8838 'demo' '1.10.0'
        try {
            $script:r = Resolve-FleetPort @common -Version '1.9.2' -Start 8838 -Policy restart -WarningVariable w -WarningAction SilentlyContinue
            $r.Action | Should -Be 'Reuse'
            $r.Port | Should -Be 8838
            $r.Note | Should -BeLike 'Stale launcher:*1.9.2*1.10.0*'
            @($w).Count | Should -Be 1
            Test-FleetSelf -Port 8838 -Tool 'demo' | Should -Not -BeNullOrEmpty
        } finally { Stop-FakeTool $t }
    }

    It 'multi policy starts another copy on the next port even when a NEWER copy is running' {
        $t = Start-FakeTool 8835 'demo' '2.0.0'
        try {
            $script:r = Resolve-FleetPort @common -Version '1.0.0' -Start 8835 -Policy multi -WarningVariable w -WarningAction SilentlyContinue
            $r.Action | Should -Be 'Start'
            $r.Port | Should -Be 8836
            @($w).Count | Should -Be 0
        } finally { Stop-FakeTool $t }
    }

    It 'does not treat a different FleetHacker tool as itself' {
        $t = Start-FakeTool 8852 'other-tool' '1.0'
        try {
            $script:r = Resolve-FleetPort @common -Version '1.0' -Start 8852 -Policy reuse
            $r.Action | Should -Be 'Start'
            $r.Port | Should -Be 8853
        } finally { Stop-FakeTool $t }
    }

    It 'exclusive policy refuses to stop another version' {
        $t = Start-FakeTool 8855 'demo' '0.9'
        try {
            { Resolve-FleetPort @common -Version '1.0' -Start 8855 -Policy exclusive } | Should -Throw -ExpectedMessage '*not stopped automatically*'
        } finally { Stop-FakeTool $t }
    }

    It 'throws a clear error when the block is full' {
        $held = @(8857, 8858, 8859 | ForEach-Object { Start-Foreign $_ })
        try {
            { Resolve-FleetPort @common -Version '1.0' -Start 8857 -Policy reuse } | Should -Throw -ExpectedMessage 'Port block 8857-8859 for demo is full*'
        } finally { $held | ForEach-Object { $_.Stop() } }
    }
}

Describe 'Get-FleetPortBlock (registry)' {
    It 'blocks in FleetPorts.psd1 do not overlap' {
        $reg = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\FleetPorts.psd1')
        $seen = @{}
        foreach ($k in $reg.Keys) {
            $b = Get-FleetPortBlock -Tool $k
            for ($p = $b.Start; $p -le $b.End; $p++) {
                $seen.ContainsKey($p) | Should -BeFalse -Because "port $p is in both $($seen[$p]) and $k"
                $seen[$p] = $k
            }
        }
    }
    It 'rejects an unknown tool' {
        { Get-FleetPortBlock -Tool 'no-such-tool' } | Should -Throw -ExpectedMessage '*has no port block*'
    }
}
