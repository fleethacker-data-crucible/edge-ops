# Pester 5, Windows PowerShell 5.1. Start-FleetService / Get-FleetServiceState against FAKE services only:
# a fake Fairlead (a PowerShell TcpListener script) and a fake TalkForge (a node script) are written to TestDrive
# and started on free ports the OS hands out, so the real Fairlead (8776) and TalkForge (25009) are never touched.
# Every fake exits by itself after 90 s, and the tests stop each one they started (only after checking its command
# line points into TestDrive). The TalkForge tests need node on PATH and are skipped without it.
BeforeDiscovery { $hasNode = [bool](Get-Command node -CommandType Application -ErrorAction SilentlyContinue) }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FleetPort.psm1') -Force
    $script:hasNode = [bool](Get-Command node -CommandType Application -ErrorAction SilentlyContinue)
    $script:token = 'fake-token-' + [guid]::NewGuid().ToString('N').Substring(0, 12)   # test value, 23 characters

    $script:fakeFairlead = @'
param([int]$Port = 0, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
[IO.File]::AppendAllText((Join-Path $root 'launches.log'), ("{0} {1}`r`n" -f $PID, ($Rest -join ' ')))
$mode = 'normal'; $mf = Join-Path $root 'mode.txt'; if (Test-Path $mf) { $mode = (Get-Content $mf -Raw).Trim() }
if ($mode -eq 'slow') { Start-Sleep -Seconds 2 }
if ($Port -le 0) { $Port = 8776 }
$tool = 'fairlead'; if ($mode -eq 'othertool') { $tool = 'semaphore' }
$idPid = $PID; if ($mode -eq 'wrongpid') { $idPid = 999999 }
$l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), $Port
$l.Start()
$until = (Get-Date).AddSeconds(90)
try {
    while ((Get-Date) -lt $until) {
        if (-not $l.Pending()) { Start-Sleep -Milliseconds 20; continue }
        $c = $l.AcceptTcpClient()
        try {
            $s = $c.GetStream(); $s.ReadTimeout = 2000
            $buf = New-Object byte[] 4096; $n = $s.Read($buf, 0, $buf.Length)
            $req = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
            $path = ($req -split ' ')[1]
            $body = '{}'; $status = '404 Not Found'
            if ($path -eq '/__fleethacker/id') {
                $o = [ordered]@{ tool = $tool; version = '9.9.9'; pid = $idPid }
                if ($mode -eq 'withpath') { $o.path = $PSCommandPath }
                if ($mode -eq 'badpath') { $o.path = 'C:\Somewhere\Else\Start-Fairlead.ps1' }
                $body = (New-Object PSObject -Property $o) | ConvertTo-Json -Compress; $status = '200 OK'
            }
            $bytes = [Text.Encoding]::UTF8.GetBytes($body)
            $head = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $status`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
            $s.Write($head, 0, $head.Length); $s.Write($bytes, 0, $bytes.Length); $s.Flush()
        } catch { } finally { $c.Close() }
    }
} finally { $l.Stop() }
'@

    $script:fakeTalkForge = @'
import { createServer } from 'node:http';
import { appendFileSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const self = fileURLToPath(import.meta.url);
const root = dirname(dirname(self));
const argv = process.argv.slice(2);
appendFileSync(join(root, 'launches.log'), `${process.pid} ${argv.join(' ')}\r\n`);
const mode = existsSync(join(root, 'mode.txt')) ? readFileSync(join(root, 'mode.txt'), 'utf8').trim() : 'normal';
const env = process.env;
writeFileSync(join(root, 'env.json'), JSON.stringify({
  tokenLength: (env.TALKFORGE_TOKEN || '').length,
  hasTokenFile: 'TALKFORGE_TOKEN_FILE' in env,
  hasLazaretteItem: 'TALKFORGE_LAZARETTE_ITEM' in env,
  hasCallerSecret: 'FLEETTEST_CALLER_TOKEN' in env,
  hasCallerApiKey: 'FLEETTEST_API_KEY' in env,
  hasPlain: env.FLEETTEST_PLAIN === 'kept'
}));
if (mode === 'exit') process.exit(3);
// More than a pipe buffer on both streams before listening: if the caller did not drain them, node would block here.
const chunk = 'x'.repeat(1024) + '\n';
for (let i = 0; i < 1024; i++) { process.stdout.write(chunk); process.stderr.write(chunk); }
const port = Number(argv[argv.indexOf('--port') + 1]);
const reported = mode === 'pagepath' ? join(root, 'Start-TalkForge.ps1') : self;
createServer((req, res) => {
  if (req.url === '/__fleethacker/id') {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ tool: 'talkforge', version: '9.9.9', pid: process.pid, path: reported }));
  }
  res.writeHead(404); res.end();
}).listen(port, '127.0.0.1');
setTimeout(() => process.exit(0), 90000).unref();
setInterval(() => {}, 1000);
'@

    function Get-FreePort {
        do {
            $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0
            $l.Start(); $p = ([Net.IPEndPoint]$l.LocalEndpoint).Port; $l.Stop()
        } while ($p -eq 8776 -or $p -eq 25009 -or -not (Test-FleetPortFree -Port $p))
        return $p
    }
    function New-FakeFolder([string]$Kind, [string]$Mode = 'normal') {
        $dir = Join-Path $TestDrive ($Kind + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        if ($Kind -eq 'fairlead') {
            [void](New-Item -ItemType Directory -Path (Join-Path $dir 'scripts') -Force)
            [IO.File]::WriteAllText((Join-Path $dir 'scripts\Start-Fairlead.ps1'), $script:fakeFairlead, [Text.Encoding]::ASCII)
        } else {
            [void](New-Item -ItemType Directory -Path (Join-Path $dir 'tools') -Force)
            [IO.File]::WriteAllText((Join-Path $dir 'tools\talkforge.mjs'), $script:fakeTalkForge, [Text.Encoding]::ASCII)
        }
        [IO.File]::WriteAllText((Join-Path $dir 'mode.txt'), $Mode, [Text.Encoding]::ASCII)
        return $dir
    }
    function Get-Launches([string]$Dir) {
        $f = Join-Path $Dir 'launches.log'
        if (-not (Test-Path $f)) { return @() }
        return @(Get-Content $f | Where-Object { $_ })
    }
    # Stops the fakes a test started: every process whose command line runs a script inside $Dir (TestDrive only).
    function Stop-Fakes([string]$Dir) {
        if (-not $Dir -or -not $Dir.StartsWith($TestDrive, [StringComparison]::OrdinalIgnoreCase)) { return }
        Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'node.exe'" |
            Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($Dir, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    function Wait-Until([scriptblock]$Condition, [int]$Seconds = 15) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt $Seconds) { if (& $Condition) { return $true }; Start-Sleep -Milliseconds 200 }
        return [bool](& $Condition)
    }
}

Describe 'Service table' {
    It 'describes Fairlead as a shell-started service on 8776 that outlives the caller' {
        $d = Get-FleetServiceDefinition -Name 'fairlead'
        $d.Port | Should -Be 8776
        $d.Launch | Should -Be 'shell'
        $d.OutlivesCaller | Should -BeTrue
        $d.Marker | Should -Be 'scripts\Start-Fairlead.ps1'
    }
    It 'describes TalkForge as a child on 25009 that needs a token of 16+ characters' {
        $d = Get-FleetServiceDefinition -Name 'TalkForge'
        $d.Port | Should -Be 25009
        $d.Launch | Should -Be 'child'
        $d.OutlivesCaller | Should -BeFalse
        $d.RequiredEnvironment['TALKFORGE_TOKEN'] | Should -Be 16
    }
    It 'matches the port registry' {
        $reg = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\FleetPorts.psd1')
        $reg['fairlead'].Start | Should -Be (Get-FleetServiceDefinition fairlead).Port
        $reg['talkforge-speech'].Start | Should -Be (Get-FleetServiceDefinition talkforge).Port
        $reg['talkforge-speech'].Size | Should -Be 1
    }
    It 'refuses an unknown service' {
        { Get-FleetServiceDefinition -Name 'nope' } | Should -Throw -ExpectedMessage "*Unknown Fleet service 'nope'*"
    }
}

Describe 'What would be started (start info)' {
    It 'Fairlead: Windows PowerShell through the shell, hidden, -File Start-Fairlead.ps1 --no-browser' {
        InModuleScope FleetPort {
            $d = Get-FleetServiceDefinition fairlead
            $si = New-FleetServiceStartInfo -Definition $d -ExePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Folder 'C:\Apps\Fairlead' -Port 8776
            $si.UseShellExecute | Should -BeTrue
            $si.WindowStyle | Should -Be 'Hidden'
            $si.Arguments | Should -BeLike '*-WindowStyle Hidden -File "C:\Apps\Fairlead\scripts\Start-Fairlead.ps1" --no-browser'
            $si.Arguments | Should -Not -BeLike '*-Port*'
            (New-FleetServiceStartInfo -Definition $d -ExePath 'x' -Folder 'C:\Apps\Fairlead' -Port 41000).Arguments | Should -BeLike '*--no-browser -Port 41000'
        }
    }
    It 'TalkForge: a hidden child, output redirected, token only in its environment, caller secrets removed' {
        $env:FLEETTEST_CALLER_TOKEN = 'caller-secret'; $env:FLEETTEST_API_KEY = 'caller-key'; $env:TALKFORGE_TOKEN_FILE = 'C:\x.txt'; $env:FLEETTEST_PLAIN = 'kept'
        try {
            InModuleScope FleetPort -Parameters @{ Tok = $script:token } {
                $d = Get-FleetServiceDefinition talkforge
                $si = New-FleetServiceStartInfo -Definition $d -ExePath 'C:\node\node.exe' -Folder 'C:\Apps\TalkForge' -Port 25009 -Environment @{ TALKFORGE_TOKEN = $Tok }
                $si.UseShellExecute | Should -BeFalse
                $si.CreateNoWindow | Should -BeTrue
                $si.RedirectStandardOutput | Should -BeTrue
                $si.RedirectStandardError | Should -BeTrue
                $si.Arguments | Should -Be '"C:\Apps\TalkForge\tools\talkforge.mjs" serve --port 25009 --idle-timeout 30'
                $si.Arguments | Should -Not -BeLike "*$Tok*"
                $si.EnvironmentVariables['TALKFORGE_TOKEN'] | Should -Be $Tok
                $si.EnvironmentVariables.ContainsKey('TALKFORGE_TOKEN_FILE') | Should -BeFalse
                $si.EnvironmentVariables.ContainsKey('FLEETTEST_CALLER_TOKEN') | Should -BeFalse
                $si.EnvironmentVariables.ContainsKey('FLEETTEST_API_KEY') | Should -BeFalse
                $si.EnvironmentVariables['FLEETTEST_PLAIN'] | Should -Be 'kept'
            }
        } finally { Remove-Item Env:FLEETTEST_CALLER_TOKEN, Env:FLEETTEST_API_KEY, Env:TALKFORGE_TOKEN_FILE, Env:FLEETTEST_PLAIN -ErrorAction SilentlyContinue }
    }
    It 'reads the script a node command line runs, and refuses one that evaluates code first' {
        InModuleScope FleetPort {
            Get-FleetNodeScriptFromCommandLine '"C:\node\node.exe" "C:\Apps\TalkForge\tools\talkforge.mjs" serve --port 1' | Should -Be 'C:\Apps\TalkForge\tools\talkforge.mjs'
            Get-FleetNodeScriptFromCommandLine 'node --no-warnings C:\a\b.mjs' | Should -Be 'C:\a\b.mjs'
            Get-FleetNodeScriptFromCommandLine 'node -e "x" C:\a\b.mjs' | Should -BeNullOrEmpty
            Get-FleetNodeScriptFromCommandLine 'node --require=C:\evil.js C:\a\b.mjs' | Should -BeNullOrEmpty
            Get-FleetNodeScriptFromCommandLine 'powershell.exe -File C:\a\b.ps1' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-FleetServiceState and the recent-start record' {
    BeforeEach { $script:state = Join-Path $TestDrive ('state-' + [guid]::NewGuid().ToString('N')); $script:port = Get-FreePort }

    It 'reports stopped when nothing listens and no start is recorded' {
        $r = Get-FleetServiceState -Name fairlead -Port $port -StateDirectory $state
        $r.State | Should -Be 'stopped'
        $r.Url | Should -Be "http://127.0.0.1:$port"
    }
    It 'reports starting while a recent start is recorded, then unavailable (timeout) once StartSeconds pass' {
        InModuleScope FleetPort -Parameters @{ S = $state; P = $port } { Set-FleetServiceStartRecord -Directory $S -Name 'fairlead' -Port $P -ProcessId 0 }
        (Get-FleetServiceState -Name fairlead -Port $port -StateDirectory $state).State | Should -Be 'starting'
        $f = Join-Path $state "fairlead-$port.json"
        $old = (Get-Content $f -Raw | ConvertFrom-Json); $old.startedAt = [datetime]::UtcNow.AddMinutes(-5).ToString('o')
        [IO.File]::WriteAllText($f, ($old | ConvertTo-Json -Compress))
        $r = Get-FleetServiceState -Name fairlead -Port $port -StateDirectory $state
        $r.State | Should -Be 'unavailable'
        $r.Reason | Should -Be 'timeout'
        (Get-FleetServiceState -Name fairlead -Port $port -StateDirectory $state).State | Should -Be 'stopped'
    }
    It 'reports unavailable (exited) when a tracked child died while starting' {
        InModuleScope FleetPort -Parameters @{ S = $state; P = $port } { Set-FleetServiceStartRecord -Directory $S -Name 'talkforge' -Port $P -ProcessId 999999 }
        $r = Get-FleetServiceState -Name talkforge -Port $port -StateDirectory $state
        $r.State | Should -Be 'unavailable'
        $r.Reason | Should -Be 'exited'
    }
}

Describe 'Start-FleetService: never on a port another program holds' {
    BeforeEach { $script:state = Join-Path $TestDrive ('state-' + [guid]::NewGuid().ToString('N')); $script:port = Get-FreePort; $script:dir = $null }
    AfterEach { Stop-Fakes $script:dir }

    It 'leaves a port held by a program that does not speak FleetHacker' {
        $script:dir = New-FakeFolder fairlead
        $t = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), $port
        $t.Start()
        try {
            $r = Start-FleetService -Name fairlead -Folder $dir -Port $port -StateDirectory $state -ProbeTimeoutMs 500
            $r.State | Should -Be 'unavailable'
            $r.Reason | Should -Be 'port-taken'
            $r.StartedHere | Should -BeFalse
            $r.Message | Should -BeLike "Port $port is in use by another program*"
            Start-Sleep -Milliseconds 500
            @(Get-Launches $dir).Count | Should -Be 0
        } finally { $t.Stop() }
    }

    It 'leaves a port held by <Mode>' -TestCases @(
        @{ Mode = 'othertool'; Like = "*FleetHacker tool 'semaphore'*" }
        @{ Mode = 'wrongpid'; Like = '*says it is fairlead pid 999999, but the port is held by*' }
        @{ Mode = 'badpath'; Like = '*is not running that file*' }
    ) {
        # The impostor is started by hand (not through the helper), then the helper is asked to make sure Fairlead runs.
        $script:dir = New-FakeFolder fairlead $Mode
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$dir\scripts\Start-Fairlead.ps1`"", '-Port', $port) | Out-Null
        Wait-Until { -not (Test-FleetPortFree -Port $port) } | Should -BeTrue
        $r = Start-FleetService -Name fairlead -Folder $dir -Port $port -StateDirectory $state
        $r.State | Should -Be 'unavailable'
        $r.Reason | Should -Be 'port-taken'
        $r.Message | Should -BeLike $Like
        @(Get-Launches $dir).Count | Should -Be 1   # only the one started by hand
    }
}

Describe 'Start-FleetService: Fairlead (shell, outlives the caller)' {
    BeforeEach { $script:state = Join-Path $TestDrive ('state-' + [guid]::NewGuid().ToString('N')); $script:port = Get-FreePort; $script:dir = $null }
    AfterEach { Stop-Fakes $script:dir }

    It 'starts it from another process that then exits, and it keeps running' {
        $script:dir = New-FakeFolder fairlead 'withpath'
        $out = Join-Path $TestDrive ('caller-' + [guid]::NewGuid().ToString('N') + '.json')
        $caller = Join-Path $TestDrive ('caller-' + [guid]::NewGuid().ToString('N') + '.ps1')
        $mod = (Get-Module FleetPort).Path
        [IO.File]::WriteAllText($caller, @"
Import-Module '$mod'
`$r = Start-FleetService -Name fairlead -Folder '$dir' -Port $port -StateDirectory '$state' -WaitSeconds 30
[IO.File]::WriteAllText('$out', (`$r | ConvertTo-Json -Compress))
"@, [Text.Encoding]::ASCII)
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $p = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$caller`"") -WindowStyle Hidden -PassThru
        $p.WaitForExit(60000) | Should -BeTrue
        $r = Get-Content $out -Raw | ConvertFrom-Json
        $r.State | Should -Be 'running'
        $r.StartedHere | Should -BeTrue
        $p.HasExited | Should -BeTrue
        Start-Sleep -Seconds 1
        $now = Get-FleetServiceState -Name fairlead -Port $port -StateDirectory $state
        $now.State | Should -Be 'running'
        $now.Pid | Should -Not -Be $p.Id
        $launch = @(Get-Launches $dir)
        $launch.Count | Should -Be 1
        $launch[0] | Should -BeLike '*--no-browser*'
        # Asking again reuses it.
        $again = Start-FleetService -Name fairlead -Folder $dir -Port $port -StateDirectory $state
        $again.State | Should -Be 'running'
        $again.StartedHere | Should -BeFalse
        @(Get-Launches $dir).Count | Should -Be 1
    }

    It 'starts it only once when four runspaces ask at the same moment' {
        $script:dir = New-FakeFolder fairlead 'slow'
        $mod = (Get-Module FleetPort).Path
        $pool = [RunspaceFactory]::CreateRunspacePool(4, 4); $pool.Open()
        $jobs = @()
        try {
            for ($i = 0; $i -lt 4; $i++) {
                $ps = [PowerShell]::Create(); $ps.RunspacePool = $pool
                [void]$ps.AddScript({ param($m, $d, $p, $s) Import-Module $m; Start-FleetService -Name fairlead -Folder $d -Port $p -StateDirectory $s }).AddArgument($mod).AddArgument($dir).AddArgument($port).AddArgument($state)
                $jobs += @{ PS = $ps; H = $ps.BeginInvoke() }
            }
            $results = @($jobs | ForEach-Object { $_.PS.EndInvoke($_.H) })
        } finally { $jobs | ForEach-Object { $_.PS.Dispose() }; $pool.Close() }
        $results.Count | Should -Be 4
        @($results | Where-Object { $_.StartedHere }).Count | Should -Be 1
        @($results | Where-Object { $_.State -eq 'starting' }).Count | Should -Be 4
        Wait-Until { (Get-FleetServiceState -Name fairlead -Port $port -StateDirectory $state).State -eq 'running' } 30 | Should -BeTrue
        @(Get-Launches $dir).Count | Should -Be 1
        # A start right after, while it is up, reuses it too.
        (Start-FleetService -Name fairlead -Folder $dir -Port $port -StateDirectory $state).StartedHere | Should -BeFalse
        @(Get-Launches $dir).Count | Should -Be 1
    }

    It 'refuses -Environment for a shell-started service' {
        $script:dir = New-FakeFolder fairlead
        $r = Start-FleetService -Name fairlead -Folder $dir -Port $port -StateDirectory $state -Environment @{ X = '1' }
        $r.State | Should -Be 'unavailable'
        $r.Reason | Should -Be 'bad-call'
        @(Get-Launches $dir).Count | Should -Be 0
    }

    It 'says where it looked when the folder is wrong, and starts nothing' {
        $missing = Join-Path $TestDrive 'no-such-fairlead'
        $r = Start-FleetService -Name fairlead -Folder $missing -Port $port -StateDirectory $state
        $r.State | Should -Be 'unavailable'
        $r.Reason | Should -Be 'not-found'
        $r.Message | Should -BeLike "*not found in $missing*"
    }

    It 'finds the folder next to the caller when none is configured' {
        $script:dir = New-FakeFolder fairlead
        $apps = Join-Path $TestDrive ('apps-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void](New-Item -ItemType Directory -Path (Join-Path $apps 'SomeApp\server') -Force)
        Copy-Item -Path $dir -Destination (Join-Path $apps 'Fairlead') -Recurse
        $script:dir = Join-Path $apps 'Fairlead'
        InModuleScope FleetPort -Parameters @{ A = $apps } {
            $f = Find-FleetServiceFolder -Definition (Get-FleetServiceDefinition fairlead) -Folder '' -CallerRoot (Join-Path $A 'SomeApp\server')
            $f.Folder | Should -Be (Join-Path $A 'Fairlead')
            $f = Find-FleetServiceFolder -Definition (Get-FleetServiceDefinition fairlead) -Folder '' -CallerRoot (Join-Path $A 'SomeApp')
            $f.Folder | Should -Be (Join-Path $A 'Fairlead')
        }
    }
}

Describe 'Start-FleetService: TalkForge (child, token in its environment)' -Skip:(-not $hasNode) {
    BeforeEach { $script:state = Join-Path $TestDrive ('state-' + [guid]::NewGuid().ToString('N')); $script:port = Get-FreePort; $script:dir = $null }
    AfterEach { [void](Stop-FleetServiceChild -Name talkforge -Port $script:port -StateDirectory $script:state); Stop-Fakes $script:dir }

    It 'starts it hidden with its output drained, the token only in its environment, and reuses it after' {
        $script:dir = New-FakeFolder talkforge
        $env:FLEETTEST_CALLER_TOKEN = 'caller-secret'; $env:FLEETTEST_API_KEY = 'caller-key'; $env:TALKFORGE_TOKEN_FILE = 'C:\x.txt'; $env:FLEETTEST_PLAIN = 'kept'
        try {
            $r = Start-FleetService -Name talkforge -Folder $dir -Port $port -StateDirectory $state -Environment @{ TALKFORGE_TOKEN = $script:token } -WaitSeconds 30
        } finally { Remove-Item Env:FLEETTEST_CALLER_TOKEN, Env:FLEETTEST_API_KEY, Env:TALKFORGE_TOKEN_FILE, Env:FLEETTEST_PLAIN -ErrorAction SilentlyContinue }
        $r.State | Should -Be 'running'          # it wrote 2 MB to stdout and stderr before listening: drained
        $r.StartedHere | Should -BeTrue
        $r.Folder | Should -Be $dir
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($r.Pid)").CommandLine
        $cmd | Should -BeLike "*$dir\tools\talkforge.mjs*serve --port $port --idle-timeout 30*"
        $cmd.Contains($script:token) | Should -BeFalse
        $seen = Get-Content (Join-Path $dir 'env.json') -Raw | ConvertFrom-Json
        $seen.tokenLength | Should -Be $script:token.Length
        $seen.hasTokenFile | Should -BeFalse
        $seen.hasCallerSecret | Should -BeFalse
        $seen.hasCallerApiKey | Should -BeFalse
        $seen.hasPlain | Should -BeTrue
        $again = Start-FleetService -Name talkforge -Folder $dir -Port $port -StateDirectory $state -Environment @{ TALKFORGE_TOKEN = $script:token }
        $again.State | Should -Be 'running'
        $again.StartedHere | Should -BeFalse
        @(Get-Launches $dir).Count | Should -Be 1
        Stop-FleetServiceChild -Name talkforge -Port $port -StateDirectory $state | Should -BeTrue
        Wait-Until { Test-FleetPortFree -Port $port } 10 | Should -BeTrue
    }

    It 'starts nothing without a token of 16+ characters' {
        $script:dir = New-FakeFolder talkforge
        foreach ($envs in @(@{}, @{ TALKFORGE_TOKEN = 'short' })) {
            $r = Start-FleetService -Name talkforge -Folder $dir -Port $port -StateDirectory $state -Environment $envs
            $r.State | Should -Be 'unavailable'
            $r.Reason | Should -Be 'no-secret'
            $r.Message | Should -Not -BeLike '*short*'
        }
        Start-Sleep -Milliseconds 500
        @(Get-Launches $dir).Count | Should -Be 0
    }

    It 'reports unavailable when it exits while starting, and tries again on the next call' {
        $script:dir = New-FakeFolder talkforge 'exit'
        $r = Start-FleetService -Name talkforge -Folder $dir -Port $port -StateDirectory $state -Environment @{ TALKFORGE_TOKEN = $script:token } -WaitSeconds 20
        $r.State | Should -Be 'unavailable'
        $r.Reason | Should -Be 'exited'
        $r.StartedHere | Should -BeTrue
        $r2 = Start-FleetService -Name talkforge -Folder $dir -Port $port -StateDirectory $state -Environment @{ TALKFORGE_TOKEN = $script:token }
        $r2.StartedHere | Should -BeTrue
        Wait-Until { @(Get-Launches $dir).Count -eq 2 } 10 | Should -BeTrue
    }

    It 'does not take TalkForge''s page server (another script) for the speech server' {
        $script:dir = New-FakeFolder talkforge 'pagepath'
        $r = Start-FleetService -Name talkforge -Folder $dir -Port $port -StateDirectory $state -Environment @{ TALKFORGE_TOKEN = $script:token } -WaitSeconds 20
        $r.State | Should -Be 'unavailable'
        $r.Reason | Should -Be 'port-taken'
        $r.Message | Should -BeLike '*another TalkForge program*Start-TalkForge.ps1*'
    }

    It 'never stops a TalkForge it did not start' {
        Stop-FleetServiceChild -Name talkforge -Port $port -StateDirectory $state | Should -BeFalse
    }
}
