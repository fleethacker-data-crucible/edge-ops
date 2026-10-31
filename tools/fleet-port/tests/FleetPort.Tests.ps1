# Pester 5. Runs on Windows PowerShell 5.1 and pwsh. Ports 8834-8859 are used as scratch blocks.
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
                    $h = Invoke-FleetIdEndpoint -Context $ctx -Tool $tool -Version $version -Path 'C:\FleetHacker\fake-tool\fake-tool.ps1'
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
    It 'keeps registry blocks out of the reserved test ranges (9300-9399 Chrome, 18000-18999 CI)' {
        $reg = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\FleetPorts.psd1')
        foreach ($k in $reg.Keys) {
            $b = Get-FleetPortBlock -Tool $k
            ($b.Start -le 9399 -and $b.End -ge 9300) | Should -BeFalse -Because "$k overlaps the test Chrome debug ports"
            ($b.Start -le 18999 -and $b.End -ge 18000) | Should -BeFalse -Because "$k overlaps the CI-only test ports"
        }
    }
    It 'gives Eight-Bells, Scrimshaw, Fairlead and Semaphore their own blocks, in step with PORTS.md' {
        $want = @{ 'eight-bells' = @(8774, 1, '8774 (1 port)'); 'scrimshaw' = @(8775, 1, '8775 (1 port)'); 'fairlead' = @(8776, 1, '8776** (1 port, fixed)'); 'semaphore' = @(8800, 3, '8800-8802') }
        $ports = Get-Content -Raw (Join-Path $PSScriptRoot '..\..\..\PORTS.md')
        $ports | Should -Not -Match '\| New tool A \|'
        foreach ($k in $want.Keys) {
            $b = Get-FleetPortBlock -Tool $k
            $b.Start | Should -Be $want[$k][0]
            ($b.End - $b.Start + 1) | Should -Be $want[$k][1]
            $ports.Contains($want[$k][2]) | Should -BeTrue -Because "PORTS.md should list $k as $($want[$k][2])"
        }
    }
    It 'rejects an unknown tool' {
        { Get-FleetPortBlock -Tool 'no-such-tool' } | Should -Throw -ExpectedMessage '*has no port block*'
    }
}

Describe 'Stop-FleetInstance forced-stop safety' {
    BeforeAll {
        $script:toolPath = 'C:\FleetHacker\demo\Start-Demo.ps1'
        # Hold the port with a silent foreign listener so the graceful shutdown never frees it.
        function Invoke-ForcedStop([string]$ReportedPath, [string]$CommandLine, [string]$ExecutablePath, [int[]]$Owners) {
            $calls = @{ Killed = @() }
            $hold = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 8834
            $hold.Start()
            try {
                $inst = New-Object PSObject -Property @{ Tool = 'demo'; Version = '0.9'; Pid = 4242; Path = $ReportedPath; Port = 8834 }
                $info = New-Object PSObject -Property @{ CommandLine = $CommandLine; ExecutablePath = $ExecutablePath }
                $ok = Stop-FleetInstance -Instance $inst -GraceMs 200 -WarningAction SilentlyContinue `
                    -GetProcessInfo ({ param($i) $null = $i; $info }.GetNewClosure()) `
                    -GetPortOwner ({ param($p) $null = $p; $Owners }.GetNewClosure()) `
                    -KillProcess ({ param($i) $calls.Killed += $i }.GetNewClosure())
            } finally { $hold.Stop() }
            return @{ Ok = $ok; Killed = @($calls.Killed) }
        }
        $script:psExe = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    It 'kills only on an exact -File match (quoted path, different case) when the pid owns the port' {
        $r = Invoke-ForcedStop $toolPath "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"c:\fleethacker\DEMO\Start-Demo.ps1`" -Port 8834" $psExe @(4242)
        $r.Killed | Should -Be @(4242)
    }

    It 'kills a compiled tool on an exact ExecutablePath match' {
        $r = Invoke-ForcedStop 'C:\FleetHacker\demo\demo.exe' '"C:\FleetHacker\demo\demo.exe" --serve' 'C:\FleetHacker\demo\demo.exe' @(4242)
        $r.Killed | Should -Be @(4242)
    }

    It "refuses when the reported path is just 'powershell'" {
        $r = Invoke-ForcedStop 'powershell' "`"$psExe`" -NoProfile" $psExe @(4242)
        $r.Ok | Should -BeFalse
        $r.Killed.Count | Should -Be 0
    }

    It 'refuses a relative reported path' {
        $r = Invoke-ForcedStop 'demo\Start-Demo.ps1' "`"$psExe`" -File demo\Start-Demo.ps1" $psExe @(4242)
        $r.Ok | Should -BeFalse
        $r.Killed.Count | Should -Be 0
    }

    It 'refuses when the path is only a non -File argument' {
        $r = Invoke-ForcedStop $toolPath "`"$psExe`" -NoProfile -Command `"& '$toolPath'`"" $psExe @(4242)
        $r.Killed.Count | Should -Be 0
        $r = Invoke-ForcedStop $toolPath "`"$psExe`" -File C:\Other\Editor.ps1 -Open `"$toolPath`"" $psExe @(4242)
        $r.Killed.Count | Should -Be 0
        $r = Invoke-ForcedStop $toolPath "notepad.exe `"$toolPath`"" 'C:\Windows\notepad.exe' @(4242)
        $r.Killed.Count | Should -Be 0
    }

    It 'reads -File after options that take a value' {
        $got = InModuleScope FleetPort { Get-FleetScriptFromCommandLine 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\t\a.ps1" -Port 1' }
        $got | Should -Be 'C:\t\a.ps1'
        InModuleScope FleetPort { Get-FleetScriptFromCommandLine 'cmd.exe /c powershell -File C:\t\a.ps1' } | Should -BeNullOrEmpty
    }

    It 'refuses a longer path that merely starts with the reported path' {
        $r = Invoke-ForcedStop 'C:\FleetHacker\demo' "`"$psExe`" -File `"C:\FleetHacker\demo\Start-Demo.ps1`"" $psExe @(4242)
        $r.Killed.Count | Should -Be 0
    }

    It 'refuses when the pid does not own the port' {
        $r = Invoke-ForcedStop $toolPath "`"$psExe`" -File `"$toolPath`"" $psExe @(4, 777)
        $r.Ok | Should -BeFalse
        $r.Killed.Count | Should -Be 0
    }
}

Describe 'Split-FleetCommandLine' {
    It 'parses quotes and backslashes like CommandLineToArgvW' -TestCases @(
        @{ Line = 'a "b c" d'; Want = @('a', 'b c', 'd') }
        @{ Line = '"C:\Program Files\x.exe" -File "C:\a b\t.ps1"'; Want = @('C:\Program Files\x.exe', '-File', 'C:\a b\t.ps1') }
        @{ Line = 'x "a\"b" c\\d'; Want = @('x', 'a"b', 'c\\d') }
        @{ Line = 'x "C:\dir\\"'; Want = @('x', 'C:\dir\') }
    ) {
        $got = InModuleScope FleetPort -Parameters @{ Line = $Line } { Split-FleetCommandLine $Line }
        ($got -join '|') | Should -Be ($Want -join '|')
        @($got).Count | Should -Be $Want.Count
    }
}

# `netsh http show servicestate view=requestq` fixtures live in tests\netsh\ (see README.md there). requestq-en-real-8845.txt
# is a real standard-user capture (pid 9720 on http://localhost:8845/); the other *-real-* files are one-edit variants of it.
Describe 'http.sys (PID 4) ports: netsh request-queue proof' {
    BeforeAll {
        $script:netshDir = Join-Path $PSScriptRoot 'netsh'
        function Get-Canned([string]$Name) { [IO.File]::ReadAllText((Join-Path $script:netshDir $Name)) }
        function Get-QueuePid([string]$Text, [int]$Port) { InModuleScope FleetPort -Parameters @{ T = $Text; P = $Port } { Get-FleetHttpSysQueuePid -Text $T -Port $P } }
        $script:toolPath = 'C:\FleetHacker\demo\Start-Demo.ps1'
        $script:psExe = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        $script:hsPort = 8845
        $script:hsPid = 9720
        # The port is held by a silent foreign listener, so the graceful shutdown never frees it; the owner is PID 4 (http.sys).
        function Invoke-HttpSysStop([string]$NetshText, $SelfAnswer = 'same', [string]$CommandLine = '', [int]$Port = $script:hsPort, [int]$ProcId = $script:hsPid) {
            if (-not $CommandLine) { $CommandLine = "`"$script:psExe`" -NoProfile -File `"$script:toolPath`"" }
            $calls = @{ Killed = @() }
            $hold = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), $Port
            $hold.Start()
            try {
                $inst = New-Object PSObject -Property @{ Tool = 'demo'; Version = '0.9'; Pid = $ProcId; Path = $script:toolPath; Port = $Port }
                $info = New-Object PSObject -Property @{ CommandLine = $CommandLine; ExecutablePath = $script:psExe }
                $self = switch ($SelfAnswer) {
                    'same' { New-Object PSObject -Property @{ IsSelf = $true; Tool = 'demo'; Pid = $ProcId } }
                    'otherpid' { New-Object PSObject -Property @{ IsSelf = $true; Tool = 'demo'; Pid = $ProcId + 1 } }
                    default { $null }
                }
                $err = $null; $ok = $null
                try {
                    $ok = Stop-FleetInstance -Instance $inst -GraceMs 200 -WarningAction SilentlyContinue `
                        -GetProcessInfo ({ param($i) $null = $i; $info }.GetNewClosure()) `
                        -GetPortOwner ({ param($p) $null = $p; @(4) }) `
                        -GetHttpSysQueues ({ $NetshText }.GetNewClosure()) `
                        -GetSelf ({ param($p, $t) $null = $p; $null = $t; $self }.GetNewClosure()) `
                        -KillProcess ({ param($i) $calls.Killed += $i }.GetNewClosure())
                } catch { $err = $_.Exception.Message }
            } finally { $hold.Stop() }
            return @{ Ok = $ok; Error = $err; Killed = @($calls.Killed) }
        }
        $script:closeMsg = 'An older demo v0.9 is still running; close its window and relaunch.*'
    }

    It 'parses the real standard-user capture: http://localhost:8845/ belongs to pid 9720' {
        $real = Get-Canned 'requestq-en-real-8845.txt'
        $real | Should -Match "`r`n"
        Get-QueuePid $real 8845 | Should -Be 9720
        Get-QueuePid ($real -replace "`r`n", "`n") 8845 | Should -Be 9720
        # FDResPub registers HTTP://*:5357/<guid>/ - a wildcard host and a non-root path, so never a proof.
        Get-QueuePid $real 5357 | Should -BeNullOrEmpty
        Get-QueuePid $real 8846 | Should -BeNullOrEmpty
    }

    It 'treats the IP-bound host:port:ip prefix (HTTP://127.0.0.1:25000:127.0.0.1/) as loopback on that port' {
        Get-QueuePid (Get-Canned 'requestq-en-real-25000-ipbound.txt') 25000 | Should -Be 10836
        Get-QueuePid (Get-Canned 'requestq-en-real-25000-ipbound-only.txt') 25000 | Should -Be 10836
        Get-QueuePid (Get-Canned 'requestq-en-real-25000-ipbound.txt') 8845 | Should -Be 9720
        Get-QueuePid (Get-Canned 'requestq-en-real-25000-ipbound-lan.txt') 25000 | Should -BeNullOrEmpty
    }

    It 'parses registered URL <Url>' -TestCases @(
        @{ Url = 'HTTP://LOCALHOST:8845/'; Port = 8845; BoundIp = $null; Path = '/'; Loopback = $true }
        @{ Url = 'HTTP://127.0.0.1:25000:127.0.0.1/'; Port = 25000; BoundIp = '127.0.0.1'; Path = '/'; Loopback = $true }
        @{ Url = 'HTTP://LOCALHOST:25000:127.0.0.1/'; Port = 25000; BoundIp = '127.0.0.1'; Path = '/'; Loopback = $true }
        @{ Url = 'HTTP://[::1]:8845/'; Port = 8845; BoundIp = $null; Path = '/'; Loopback = $true }
        @{ Url = 'HTTP://[::1]:8845:[::1]/'; Port = 8845; BoundIp = '::1'; Path = '/'; Loopback = $true }
        @{ Url = 'HTTP://127.0.0.1:25000:10.0.0.5/'; Port = 25000; BoundIp = '10.0.0.5'; Path = '/'; Loopback = $false }
        @{ Url = 'HTTP://10.0.0.5:25000:10.0.0.5/'; Port = 25000; BoundIp = '10.0.0.5'; Path = '/'; Loopback = $false }
        @{ Url = 'HTTP://*:5357/00000000-0000-0000-0000-000000000000/'; Port = 5357; BoundIp = $null; Path = '/00000000-0000-0000-0000-000000000000/'; Loopback = $false }
        @{ Url = 'HTTP://+:8845/'; Port = 8845; BoundIp = $null; Path = '/'; Loopback = $false }
        @{ Url = 'HTTP://LOCALHOST:8845/legacy/'; Port = 8845; BoundIp = $null; Path = '/legacy/'; Loopback = $true }
    ) {
        $u = InModuleScope FleetPort -Parameters @{ U = $Url } { ConvertFrom-FleetHttpSysUrl $U }
        $u | Should -Not -BeNullOrEmpty
        $u.Port | Should -Be $Port
        $u.BoundIp | Should -Be $BoundIp
        $u.Path | Should -Be $Path
        $u.Loopback | Should -Be $Loopback
    }

    It 'rejects unparseable URL <Url>' -TestCases @(
        @{ Url = 'HTTP://LOCALHOST:88X45/' }
        @{ Url = 'HTTP://LOCALHOST/' }
        @{ Url = 'HTTP://LOCALHOST:70000/' }
        @{ Url = 'HTTP://LOCALHOST:8845' }
    ) {
        InModuleScope FleetPort -Parameters @{ U = $Url } { ConvertFrom-FleetHttpSysUrl $U } | Should -BeNullOrEmpty
    }

    It 'refuses to identify a queue from <Name>' -TestCases @(
        @{ Name = 'requestq-en-real-8845-malformed.txt' }
        @{ Name = 'requestq-en-real-8845-emptyqueue.txt' }
        @{ Name = 'requestq-en-real-8845-twoprocs.txt' }
        @{ Name = 'requestq-en-real-8845-ambiguous.txt' }
        @{ Name = 'requestq-en-real-8845-legacy.txt' }
        @{ Name = 'requestq-en-real-8845-twoqueues.txt' }
        @{ Name = 'requestq-en-real-8845-badurl.txt' }
        @{ Name = 'requestq-accessdenied.txt' }
        @{ Name = 'requestq-de-real-8845.txt' }
    ) {
        Get-QueuePid (Get-Canned $Name) 8845 | Should -BeNullOrEmpty
    }

    It 'force-stops a well-formed older copy when all four proof conditions pass (real capture)' {
        $r = Invoke-HttpSysStop (Get-Canned 'requestq-en-real-8845.txt')
        $r.Error | Should -BeNullOrEmpty
        $r.Killed | Should -Be @(9720)
    }

    It 'force-stops a TalkForge-style queue that also registers the IP-bound loopback prefix' {
        $r = Invoke-HttpSysStop (Get-Canned 'requestq-en-real-25000-ipbound.txt') -Port 8847 -ProcId 10836
        $r.Error | Should -BeLike '*could not be identified*'
        $r.Killed.Count | Should -Be 0
        $text = (Get-Canned 'requestq-en-real-25000-ipbound.txt') -replace ':25000', ':8847'
        $r = Invoke-HttpSysStop $text -Port 8847 -ProcId 10836
        $r.Error | Should -BeNullOrEmpty
        $r.Killed | Should -Be @(10836)
    }

    It 'refuses with the close-it-yourself message when the queue belongs to another pid' {
        $r = Invoke-HttpSysStop (Get-Canned 'requestq-en-real-8845-otherpid.txt')
        $r.Killed.Count | Should -Be 0
        $r.Error | Should -BeLike $closeMsg
        $r.Error | Should -BeLike '*held by pid 5555*'
    }

    It 'refuses with the message for <Name>' -TestCases @(
        @{ Name = 'requestq-en-real-8845-malformed.txt' }
        @{ Name = 'requestq-en-real-8845-emptyqueue.txt' }
        @{ Name = 'requestq-en-real-8845-twoprocs.txt' }
        @{ Name = 'requestq-en-real-8845-ambiguous.txt' }
        @{ Name = 'requestq-en-real-8845-legacy.txt' }
        @{ Name = 'requestq-en-real-8845-twoqueues.txt' }
        @{ Name = 'requestq-en-real-8845-badurl.txt' }
        @{ Name = 'requestq-accessdenied.txt' }
        @{ Name = 'requestq-de-real-8845.txt' }
    ) {
        $r = Invoke-HttpSysStop (Get-Canned $Name)
        $r.Killed.Count | Should -Be 0
        $r.Error | Should -BeLike $closeMsg
    }

    It 'refuses with the message when netsh fails (no output)' {
        $r = Invoke-HttpSysStop $null
        $r.Killed.Count | Should -Be 0
        $r.Error | Should -BeLike $closeMsg
    }

    It 'refuses when /__fleethacker/id no longer answers or reports another pid' {
        foreach ($answer in 'none', 'otherpid') {
            $r = Invoke-HttpSysStop (Get-Canned 'requestq-en-real-8845.txt') $answer
            $r.Killed.Count | Should -Be 0
            $r.Error | Should -BeLike $closeMsg
        }
    }

    It 'still requires the exact -File path even when the queue matches' {
        $r = Invoke-HttpSysStop (Get-Canned 'requestq-en-real-8845.txt') 'same' "`"$psExe`" -NoProfile -Command `"& '$toolPath'`""
        $r.Killed.Count | Should -Be 0
        $r.Ok | Should -BeFalse
    }

    It 'Resolve-FleetPort passes the message through and starts nothing' {
        $reg = Join-Path ([IO.Path]::GetTempPath()) ('fp-' + [guid]::NewGuid().ToString('N') + '.psd1')
        Set-Content -LiteralPath $reg -Value "@{ 'demo' = @{ Start = 8836; Size = 1; Policy = 'reuse' } }" -Encoding Ascii
        $fake = Start-FakeTool -Port 8836 -Tool 'demo' -Version '0.9'
        try {
            { Resolve-FleetPort -Tool 'demo' -Version '1.0' -RegistryPath $reg -NoListener -StopInstance { param($i, $g) $null = $g; throw "An older $($i.Tool) v$($i.Version) is still running; close its window and relaunch." } } |
                Should -Throw -ExpectedMessage 'An older demo v0.9 is still running; close its window and relaunch.'
        } finally { Stop-FakeTool $fake; Remove-Item -LiteralPath $reg -ErrorAction SilentlyContinue }
    }
}
