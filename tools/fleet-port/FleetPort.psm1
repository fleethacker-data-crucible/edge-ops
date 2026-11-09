<#
.SYNOPSIS
    FleetHacker port blocks with self-detection (Windows PowerShell 5.1). ASCII only.
.DESCRIPTION
    Each tool owns one contiguous port block (FleetPorts.psd1). It starts at the block's first port and
    walks upward only inside its block. When a port is busy it probes GET /__fleethacker/id first:
      - another program, or no answer   -> next port in the block
      - this same tool                  -> apply the tool's policy:
          (any policy but multi) a NEWER copy is running: Action 'Reuse' with a 'stale launcher' Note
                    (also written as a warning); never downgrade
          reuse     same version: return Action 'Reuse' (open the browser to it and exit);
                    older or unparseable version: stop it gracefully, then start on that port
          restart   always stop it gracefully, then start on that port
          multi     leave it running, try the next port (whatever its version: built for parallelism)
          exclusive same version: Reuse; older version: throw (never auto-stop; holds a lease)
    Block full -> a clear error. Binds http://localhost:<port>/ only. No random or OS-ephemeral fallback.
    Graceful stop: POST /__fleethacker/shutdown (header X-FleetHacker-Shutdown: 1). If the port is still
    held, Stop-Process only on the self-reported pid, and only when the reported path is absolute, it EXACTLY
    equals that pid's -File script (parsed from Win32_Process.CommandLine) or ExecutablePath, and that pid
    owns the listening port. Never a substring match.
    Functions: Get-FleetPortBlock, Test-FleetPortFree, Test-FleetSelf, Stop-FleetInstance, Resolve-FleetPort,
               Invoke-FleetIdEndpoint (drop-in for an HttpListener request loop).
#>
Set-StrictMode -Version Latest

$script:IdPath = '/__fleethacker/id'
$script:ShutdownPath = '/__fleethacker/shutdown'
$script:Policies = @('reuse', 'restart', 'multi', 'exclusive')

function Get-FleetPortBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [string]$RegistryPath = (Join-Path $PSScriptRoot 'FleetPorts.psd1')
    )
    $reg = Import-PowerShellDataFile -LiteralPath $RegistryPath
    if (-not $reg.ContainsKey($Tool)) { throw "Tool '$Tool' has no port block in $RegistryPath. Add one (see PORTS.md)." }
    $b = $reg[$Tool]
    $policy = [string]$b.Policy
    if ($script:Policies -notcontains $policy) { throw "Tool '$Tool' has an unknown policy '$policy' (use $($script:Policies -join ', '))." }
    $start = [int]$b.Start; $size = [int]$b.Size
    if ($size -lt 1) { throw "Tool '$Tool' block size must be at least 1." }
    New-Object PSObject -Property ([ordered]@{ Tool = $Tool; Start = $start; End = $start + $size - 1; Size = $size; Policy = $policy })
}

# Free on both IPv4 and IPv6 loopback. A machine without IPv6 counts as free on that side.
function Test-FleetPortFree {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)][int]$Port)
    foreach ($addr in @([System.Net.IPAddress]::Loopback, [System.Net.IPAddress]::IPv6Loopback)) {
        $t = New-Object System.Net.Sockets.TcpListener $addr, $Port
        try { $t.Start(); $t.Stop() }
        catch [System.Net.Sockets.SocketException] {
            if ($addr.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6 -and
                $_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::AddressFamilyNotSupported) { continue }
            return $false
        }
    }
    return $true
}

function Invoke-FleetLocalRequest {
    param([int]$Port, [string]$Path, [string]$Method = 'GET', [int]$TimeoutMs = 1500, [hashtable]$Headers = @{})
    # Try 127.0.0.1 first, then [::1] only if IPv4 refused the connection. Always send Host: localhost:<port>,
    # which http.sys needs to match a localhost prefix. (Going to ::1 first would cost ~2 s on Windows,
    # which retries a refused connect.)
    foreach ($ip in @('127.0.0.1', '[::1]')) {
        try {
            $req = [System.Net.HttpWebRequest]::Create("http://${ip}:$Port$Path")
            $req.Host = "localhost:$Port"
            $req.Method = $Method
            $req.Proxy = $null                      # never send loopback probes through a proxy
            $req.Timeout = $TimeoutMs
            $req.ReadWriteTimeout = $TimeoutMs
            $req.AllowAutoRedirect = $false
            foreach ($k in $Headers.Keys) { $req.Headers[$k] = [string]$Headers[$k] }
            if ($Method -eq 'POST') { $req.ContentLength = 0 }
            $resp = $req.GetResponse()
            try {
                $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $body = $sr.ReadToEnd()
                return New-Object PSObject -Property @{ Status = [int]$resp.StatusCode; Body = $body }
            } finally { $resp.Close() }
        } catch [System.Net.WebException] {
            $we = $_.Exception
            if ($we -isnot [System.Net.WebException] -and $we.InnerException -is [System.Net.WebException]) { $we = $we.InnerException }
            $r = $we.Response
            if ($r) { $code = [int]$r.StatusCode; $r.Close(); return New-Object PSObject -Property @{ Status = $code; Body = '' } }
            # Refused is ConnectFailure on .NET Framework and UnknownError on .NET Core; a timeout means
            # something holds the IPv4 port, so do not spend another timeout on ::1.
            if ($we.Status -eq [System.Net.WebExceptionStatus]::Timeout) { return $null }
        } catch {
            return $null
        }
    }
    return $null
}

# Probes GET /__fleethacker/id. Returns $null when nothing FleetHacker answers, else
# @{ IsSelf; Tool; Version; Pid; Path }.
function Test-FleetSelf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Tool,
        [int]$TimeoutMs = 1500
    )
    $r = Invoke-FleetLocalRequest -Port $Port -Path $script:IdPath -TimeoutMs $TimeoutMs
    if (-not $r -or $r.Status -ne 200 -or -not $r.Body) { return $null }
    try { $id = $r.Body | ConvertFrom-Json } catch { return $null }
    if (-not $id -or -not ($id.PSObject.Properties.Name -contains 'tool')) { return $null }
    $path = $null; if ($id.PSObject.Properties.Name -contains 'path') { $path = [string]$id.path }
    $procId = 0; if ($id.PSObject.Properties.Name -contains 'pid') { $procId = [int]$id.pid }
    $ver = ''; if ($id.PSObject.Properties.Name -contains 'version') { $ver = [string]$id.version }
    New-Object PSObject -Property ([ordered]@{
        IsSelf = ([string]$id.tool -eq $Tool); Tool = [string]$id.tool; Version = $ver; Pid = $procId; Path = $path; Port = $Port })
}

# 1 if A is newer than B, -1 if older, 0 if equal, $null if either is not a dotted version
# (a leading 'v' and a '-suffix' / '+build' are ignored). Unknown counts as "different", never "newer".
function Compare-FleetVersion {
    param([string]$A, [string]$B)
    $va = ConvertTo-FleetVersion $A; $vb = ConvertTo-FleetVersion $B
    if ($null -eq $va -or $null -eq $vb) { return $null }
    return $va.CompareTo($vb)
}

function ConvertTo-FleetVersion {
    param([string]$Text)
    if ($Text -notmatch '^\s*v?(\d+(\.\d+){0,3})') { return $null }
    $t = $Matches[1]; if ($t -notmatch '\.') { $t = "$t.0" }
    $v = $null
    if ([System.Version]::TryParse($t, [ref]$v)) { return $v }
    return $null
}

function Wait-FleetPortFree {
    param([int]$Port, [int]$TimeoutMs)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        if (Test-FleetPortFree -Port $Port) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return (Test-FleetPortFree -Port $Port)
}

# Absolute, normalized Windows path (drive root 'C:\...' or UNC '\\server\share\...'), or $null.
# Relative or bare values such as 'powershell' or 'tool.ps1' are rejected.
function ConvertTo-FleetAbsolutePath {
    param([string]$Path)
    if (-not $Path) { return $null }
    $p = $Path.Trim().Trim('"').Replace('/', '\')
    if ($p -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\?.]+\\[^\\]+)') { return $null }
    if ($env:OS -eq 'Windows_NT') {
        try { $p = [System.IO.Path]::GetFullPath($p) } catch { return $null }
    } elseif ($p -match '\\\.{1,2}(\\|$)') {
        return $null                            # cannot normalize '.' / '..' segments off Windows; refuse
    }
    return $p.TrimEnd('\')
}

# Splits a Windows command line the way CommandLineToArgvW / the MSVC runtime does:
# whitespace separates arguments; "..." groups; 2n backslashes + quote -> n backslashes and a quote toggle;
# 2n+1 backslashes + quote -> n backslashes and a literal quote; other backslashes are literal.
function Split-FleetCommandLine {
    param([string]$CommandLine)
    $out = New-Object System.Collections.Generic.List[string]
    if (-not $CommandLine) { return , $out.ToArray() }
    $sb = New-Object System.Text.StringBuilder
    $inQuote = $false; $have = $false; $i = 0; $n = $CommandLine.Length
    while ($i -lt $n) {
        $c = $CommandLine[$i]
        if ($c -eq '\') {
            $j = $i; while ($j -lt $n -and $CommandLine[$j] -eq '\') { $j++ }
            $count = $j - $i
            if ($j -lt $n -and $CommandLine[$j] -eq '"') {
                [void]$sb.Append('\', [int][Math]::Floor($count / 2))
                if ($count % 2 -eq 1) { [void]$sb.Append('"'); $i = $j + 1 } else { $i = $j }
            } else { [void]$sb.Append('\', $count); $i = $j }
            $have = $true; continue
        }
        if ($c -eq '"') {
            if ($inQuote -and ($i + 1) -lt $n -and $CommandLine[$i + 1] -eq '"') { [void]$sb.Append('"'); $i += 2; $have = $true; continue }
            $inQuote = -not $inQuote; $have = $true; $i++; continue
        }
        if (-not $inQuote -and ($c -eq ' ' -or $c -eq "`t")) {
            if ($have) { $out.Add($sb.ToString()); [void]$sb.Clear(); $have = $false }
            $i++; continue
        }
        [void]$sb.Append($c); $have = $true; $i++
    }
    if ($have) { $out.Add($sb.ToString()) }
    return , $out.ToArray()
}

# The script passed to powershell.exe / pwsh.exe with -File (or -f), or $null. Returns $null when the host is not
# PowerShell, or when -Command / -EncodedCommand comes first (then the path is only an argument, not the script).
function Get-FleetScriptFromCommandLine {
    param([string]$CommandLine)
    [string[]]$argv = Split-FleetCommandLine $CommandLine
    if ($null -eq $argv -or $argv.Count -lt 3) { return $null }
    $exeLeaf = ($argv[0] -split '[\\/]')[-1]
    if (@('powershell', 'powershell.exe', 'pwsh', 'pwsh.exe') -notcontains $exeLeaf.ToLowerInvariant()) { return $null }
    for ($k = 1; $k -lt $argv.Count - 1; $k++) {
        $a = $argv[$k].ToLowerInvariant()
        if ($a -eq '-file' -or $a -eq '-f' -or $a -eq '/file') { return $argv[$k + 1] }
        if ($a -match '^[-/](c|command|e|ec|encodedcommand|commandwithargs|cwa)$') { return $null }
        if ($a -match '^[-/](executionpolicy|ep|ex|windowstyle|w|version|v|inputformat|if|outputformat|of|psconsolefile|configurationname|workingdirectory|wd|settingsfile)$') { $k++; continue }
        if ($a -notmatch '^[-/]') { return $null }   # a bare argument before -File: not a -File launch
    }
    return $null
}

# $true only when the process IS the tool at $Path: an exact (case-insensitive) match of the normalized path
# against the -File script of a PowerShell host, or against ExecutablePath for a compiled tool. Never a substring.
function Test-FleetProcessIdentity {
    param([string]$Path, [string]$CommandLine, [string]$ExecutablePath)
    $want = ConvertTo-FleetAbsolutePath $Path
    if (-not $want) { return $false }
    $exe = ConvertTo-FleetAbsolutePath $ExecutablePath
    if ($exe -and [string]::Equals($exe, $want, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $script = ConvertTo-FleetAbsolutePath (Get-FleetScriptFromCommandLine $CommandLine)
    if ($script -and [string]::Equals($script, $want, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

function Get-FleetProcessInfo {
    param([int]$ProcessId)
    $p = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
    if (-not $p) { return $null }
    New-Object PSObject -Property @{ CommandLine = [string]$p.CommandLine; ExecutablePath = [string]$p.ExecutablePath }
}

# PIDs listening on the port. Empty when unknown (no Get-NetTCPConnection), which makes Stop-FleetInstance refuse.
# Note: an http.sys (HttpListener) port is owned by PID 4 (System); see Stop-FleetInstance for the netsh proof.
function Get-FleetPortOwner {
    param([int]$Port)
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) { return @() }
    @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.OwningProcess } | Sort-Object -Unique)
}

# Raw `netsh http show servicestate view=requestq` output, or $null when netsh is missing or fails
# (non-zero exit, for example access denied). Read-only.
function Get-FleetHttpSysRequestQueueText {
    $sys = [Environment]::SystemDirectory
    if (-not $sys) { return $null }
    $netsh = Join-Path $sys 'netsh.exe'
    if (-not (Test-Path -LiteralPath $netsh)) { return $null }
    try { $out = & $netsh http show servicestate view=requestq 2>&1 } catch { return $null }
    if ($LASTEXITCODE -ne 0) { return $null }
    return (@($out | ForEach-Object { [string]$_ }) -join "`n")
}

<#
  One URL from the "Registered URLs:" list, parsed deliberately, or $null when it is not a form we understand.
  Forms (http.sys URL prefix strings, as netsh prints them in upper case):
    HTTP://LOCALHOST:8845/                  host:port
    HTTP://127.0.0.1:25000:127.0.0.1/       host:port:ip (IP-bound prefix; TalkForge registers this form)
    HTTP://[::1]:8845/                      bracketed IPv6 host
    Wildcard hosts (* or +), e.g. ports 5357 and 80; never loopback.
  Returns @{ Scheme; Host; Port; BoundIp; Path; Loopback }. Loopback is true only when the host is localhost,
  127.0.0.1 or [::1] AND, for the host:port:ip form, the bound ip is 127.0.0.1 or ::1 too. + and * are never loopback.
#>
function ConvertFrom-FleetHttpSysUrl {
    param([string]$Url)
    $m = [regex]::Match([string]$Url, '^(?i)(https?)://(\[[0-9a-f:.]+\]|[^:/\[\]]+):(\d{1,5})(?::(\[[0-9a-f:.]+\]|[0-9a-f:.]+))?(/.*)$')
    if (-not $m.Success) { return $null }
    $port = [int]$m.Groups[3].Value
    if ($port -lt 1 -or $port -gt 65535) { return $null }
    $hostName = $m.Groups[2].Value.ToLowerInvariant()
    $boundIp = $null
    if ($m.Groups[4].Success) { $boundIp = $m.Groups[4].Value.Trim('[', ']').ToLowerInvariant() }
    $loopHosts = @('localhost', '127.0.0.1', '[::1]')
    $loop = ($loopHosts -contains $hostName)
    if ($loop -and $null -ne $boundIp) { $loop = (@('127.0.0.1', '::1') -contains $boundIp) }
    return @{ Scheme = $m.Groups[1].Value.ToLowerInvariant(); Host = $hostName; Port = $port; BoundIp = $boundIp; Path = $m.Groups[5].Value; Loopback = [bool]$loop }
}

<#
  Pid of the http.sys request queue that serves <Port> only on loopback, or $null unless that is certain.
  Only the English layout is understood ("Snapshot of HTTP service state (Request Queue View):", "Request queue name:",
  "ID: <pid>, image: ...", and the registered URL lines, which real output nests under "URL groups:").
  Every registered URL is parsed with ConvertFrom-FleetHttpSysUrl and matched on its port number, so the host:port:ip
  form (HTTP://127.0.0.1:25000:127.0.0.1/) counts as being on port 25000 rather than slipping past a text match.
  Refuses ($null) when: the header is missing (other language, error text, access denied), any URL line cannot be
  parsed, no queue or more than one queue registers a URL on that port, any URL on that port is not plain http with
  a loopback host (localhost, 127.0.0.1, [::1]; for host:port:ip the ip must be loopback too) or has a path other than
  "/" (for example an extra /legacy/ prefix), or the queue does not list exactly one process.
#>
function Get-FleetHttpSysQueuePid {
    param([string]$Text, [int]$Port)
    if (-not $Text -or $Text -notmatch '(?m)^\s*Snapshot of HTTP service state \(Request Queue View\):\s*$') { return $null }
    $queues = New-Object System.Collections.Generic.List[object]
    $cur = $null
    foreach ($raw in ($Text -split "`r?`n")) {
        $line = $raw.TrimEnd()
        if ($line -match '^Request queue name:') { $cur = @{ Pids = New-Object System.Collections.Generic.List[int]; Urls = New-Object System.Collections.Generic.List[object]; Attached = -1; Bad = $false }; $queues.Add($cur); continue }
        if (-not $cur) { continue }
        if ($line -match '^\s+Number of active processes attached:\s*(\d+)\s*$') { $cur.Attached = [int]$Matches[1]; continue }
        if ($line -match '^\s+ID:\s*(\d+),\s*image:') { $cur.Pids.Add([int]$Matches[1]); continue }
        if ($line -match '^\s+(HTTPS?://\S+)$') {
            $u = ConvertFrom-FleetHttpSysUrl $Matches[1]
            if ($u) { $cur.Urls.Add($u) } else { $cur.Bad = $true }
        }
    }
    # A URL line we cannot parse could be on this port, so it makes the whole answer uncertain.
    if (@($queues | Where-Object { $_.Bad }).Count -gt 0) { return $null }
    $onPort = @($queues | Where-Object { @($_.Urls | Where-Object { $_.Port -eq $Port }).Count -gt 0 })
    if ($onPort.Count -ne 1) { return $null }
    $q = $onPort[0]
    foreach ($u in @($q.Urls | Where-Object { $_.Port -eq $Port })) {
        if ($u.Scheme -ne 'http' -or -not $u.Loopback -or $u.Path -ne '/') { return $null }
    }
    $pids = @($q.Pids | Sort-Object -Unique)
    if ($pids.Count -ne 1) { return $null }
    if ($q.Attached -ne -1 -and $q.Attached -ne 1) { return $null }
    return [int]$pids[0]
}

# Graceful first (shutdown endpoint). If the port is still held after GraceMs, Stop-Process is used only when ALL hold:
#   - the self-reported path is absolute and normalized,
#   - the self-reported pid is not this process,
#   - that pid IS the tool (Test-FleetProcessIdentity: exact -File script or ExecutablePath match),
#   - that pid owns the listening port (Get-NetTCPConnection), OR the port is owned only by PID 4 (http.sys) and
#     the netsh request queue serving that port only on loopback belongs to exactly that pid (Get-FleetHttpSysQueuePid),
#   - and, for http.sys, /__fleethacker/id on the port still reports the same tool and pid just before the kill.
# Otherwise it refuses with a warning and returns $false. For an http.sys port whose proof fails it THROWS (nothing is
# killed): "An older <Tool> v<X> is still running; close its window and relaunch." The script blocks are for tests.
function Stop-FleetInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Instance,
        [int]$GraceMs = 5000,
        [switch]$NoForce,
        [scriptblock]$GetProcessInfo = { param($i) Get-FleetProcessInfo -ProcessId $i },
        [scriptblock]$GetPortOwner = { param($p) Get-FleetPortOwner -Port $p },
        [scriptblock]$KillProcess = { param($i) Stop-Process -Id $i -Force -ErrorAction SilentlyContinue },
        [scriptblock]$GetHttpSysQueues = { Get-FleetHttpSysRequestQueueText },
        [scriptblock]$GetSelf = { param($p, $t) Test-FleetSelf -Port $p -Tool $t }
    )
    [void](Invoke-FleetLocalRequest -Port $Instance.Port -Path $script:ShutdownPath -Method 'POST' -Headers @{ 'X-FleetHacker-Shutdown' = '1' })
    if (Wait-FleetPortFree -Port $Instance.Port -TimeoutMs $GraceMs) { return $true }
    if ($NoForce) { return $false }
    $procId = [int]$Instance.Pid
    $tag = "$($Instance.Tool) pid $procId on port $($Instance.Port)"
    if ($procId -le 4 -or $procId -eq $PID) { Write-Warning "Not stopping ${tag}: invalid pid."; return $false }
    $path = ConvertTo-FleetAbsolutePath $Instance.Path
    if (-not $path) { Write-Warning "Not stopping ${tag}: reported path '$($Instance.Path)' is not an absolute path."; return $false }
    $info = & $GetProcessInfo $procId
    if (-not $info) { Write-Warning "Not stopping ${tag}: process not found."; return $false }
    if (-not (Test-FleetProcessIdentity -Path $path -CommandLine $info.CommandLine -ExecutablePath $info.ExecutablePath)) {
        Write-Warning "Not stopping ${tag}: it is not '$path' (no exact -File or executable match)."; return $false
    }
    $owners = @(& $GetPortOwner $Instance.Port)
    if ($owners.Count -eq 1 -and $owners[0] -eq 4) {
        # http.sys holds the port for the HttpListener process. Kill only with the request-queue proof.
        $closeMsg = "An older $($Instance.Tool) v$($Instance.Version) is still running; close its window and relaunch."
        $queuePid = Get-FleetHttpSysQueuePid -Text ([string](& $GetHttpSysQueues)) -Port $Instance.Port
        if ($null -eq $queuePid) { throw "$closeMsg (pid $procId on port $($Instance.Port) ignored the shutdown request; its http.sys request queue could not be identified with certainty from 'netsh http show servicestate view=requestq', so nothing was stopped.)" }
        if ($queuePid -ne $procId) { throw "$closeMsg (pid $procId on port $($Instance.Port) ignored the shutdown request; netsh shows the request queue for port $($Instance.Port) held by pid $queuePid, so nothing was stopped.)" }
        $again = & $GetSelf $Instance.Port $Instance.Tool
        if (-not $again -or -not $again.IsSelf -or [int]$again.Pid -ne $procId) { throw "$closeMsg (pid $procId on port $($Instance.Port): /__fleethacker/id no longer reports that tool and pid, so nothing was stopped.)" }
        & $KillProcess $procId
        return (Wait-FleetPortFree -Port $Instance.Port -TimeoutMs 3000)
    }
    if ($owners -notcontains $procId) {
        Write-Warning "Not stopping ${tag}: the port is held by pid(s) '$($owners -join ', ')', not $procId."; return $false
    }
    & $KillProcess $procId
    return (Wait-FleetPortFree -Port $Instance.Port -TimeoutMs 3000)
}

function Start-FleetHttpListener {
    param([int]$Port)
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://localhost:$Port/")
    try { $l.Start(); return $l } catch { $l.Close(); return $null }
}

<#
.SYNOPSIS
    Walks the tool's block and applies its policy. Returns @{ Action = 'Start'|'Reuse'; Port; Url; Listener; Existing; Note }. Log Note when it is set.
    Action 'Start': Listener is a started HttpListener on http://localhost:<Port>/ (or $null with -NoListener; bind it yourself).
    Action 'Reuse': open Url in the browser and exit.
#>
function Resolve-FleetPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(Mandatory = $true)][string]$Version,
        [int]$Start = 0,
        [int]$Size = 0,
        [ValidateSet('', 'reuse', 'restart', 'multi', 'exclusive')][string]$Policy = '',
        [string]$RegistryPath = (Join-Path $PSScriptRoot 'FleetPorts.psd1'),
        [int]$ProbeTimeoutMs = 1500,
        [int]$GraceMs = 5000,
        [switch]$NoListener,
        [scriptblock]$StopInstance = { param($i, $g) Stop-FleetInstance -Instance $i -GraceMs $g }
    )
    if ($Start -gt 0 -and $Size -gt 0 -and $Policy) {
        $block = New-Object PSObject -Property @{ Tool = $Tool; Start = $Start; End = $Start + $Size - 1; Size = $Size; Policy = $Policy }
    } else {
        $block = Get-FleetPortBlock -Tool $Tool -RegistryPath $RegistryPath
        if ($Start -gt 0) { $block.Start = $Start; $block.End = $Start + $block.Size - 1 }
        if ($Size -gt 0) { $block.Size = $Size; $block.End = $block.Start + $Size - 1 }
        if ($Policy) { $block.Policy = $Policy }
    }
    $notes = New-Object System.Collections.Generic.List[string]
    for ($p = $block.Start; $p -le $block.End; $p++) {
        if (Test-FleetPortFree -Port $p) {
            $r = Get-FleetStartResult -Port $p -NoListener:$NoListener
            if ($r) { return $r }
        }
        $id = Test-FleetSelf -Port $p -Tool $Tool -TimeoutMs $ProbeTimeoutMs
        if (-not $id) { $notes.Add("${p}: in use by another program"); continue }
        if (-not $id.IsSelf) { $notes.Add("${p}: in use by FleetHacker tool '$($id.Tool)'"); continue }
        $same = ($id.Version -eq $Version)
        $stop = $false
        if ($block.Policy -ne 'multi' -and -not $same -and (Compare-FleetVersion $id.Version $Version) -gt 0) {
            # Never downgrade: a newer copy is already running, so this launcher is stale.
            $note = "Stale launcher: $Tool $Version was started, but newer $Tool $($id.Version) is already running on port $p (pid $($id.Pid)); reusing it."
            Write-Warning $note
            return (New-FleetReuse $p $id $note)
        }
        switch ($block.Policy) {
            'multi'     { $notes.Add("${p}: another $Tool instance (multi)"); continue }
            'reuse'     { if ($same) { return (New-FleetReuse $p $id) } else { $stop = $true } }
            'exclusive' {
                if ($same) { return (New-FleetReuse $p $id) }
                throw "$Tool $($id.Version) is already running on port $p (pid $($id.Pid)). It holds a lease, so it is not stopped automatically. Close it, then start $Tool $Version."
            }
            'restart'   { $stop = $true }
        }
        if ($stop) {
            if (& $StopInstance $id $GraceMs) {
                $r = Get-FleetStartResult -Port $p -NoListener:$NoListener
                if ($r) { return $r }
            }
            $notes.Add("${p}: $Tool $($id.Version) (pid $($id.Pid)) did not stop")
        }
    }
    throw ("Port block $($block.Start)-$($block.End) for $Tool is full: " + ($notes -join '; ') + '. Close one of these programs, or change the block in PORTS.md.')
}

function New-FleetReuse {
    param([int]$Port, $Existing, [string]$Note = '')
    New-Object PSObject -Property ([ordered]@{ Action = 'Reuse'; Port = $Port; Url = "http://localhost:$Port/"; Listener = $null; Existing = $Existing; Note = $Note })
}

function Get-FleetStartResult {
    param([int]$Port, [switch]$NoListener)
    $l = $null
    if (-not $NoListener) { $l = Start-FleetHttpListener -Port $Port; if (-not $l) { return $null } }
    New-Object PSObject -Property ([ordered]@{ Action = 'Start'; Port = $Port; Url = "http://localhost:$Port/"; Listener = $l; Existing = $null; Note = '' })
}

<#
.SYNOPSIS
    Drop-in for an HttpListener loop. Returns 'id', 'shutdown' or 'denied' when it answered the request
    (the response is already closed), else $null (not a /__fleethacker/ path; handle it yourself).
    On 'shutdown' the caller stops its listener and exits.
.EXAMPLE
    $ctx = $listener.GetContext()
    $h = Invoke-FleetIdEndpoint -Context $ctx -Tool 'lasso' -Version $version -Path $PSCommandPath
    if ($h -eq 'shutdown') { $listener.Stop(); break }
    if ($h) { continue }
#>
function Invoke-FleetIdEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(Mandatory = $true)][string]$Version,
        [string]$Path = ''
    )
    $req = $Context.Request
    $local = $req.Url.AbsolutePath
    if ($local -ne $script:IdPath -and $local -ne $script:ShutdownPath) { return $null }
    $res = $Context.Response
    $origin = $req.Headers['Origin']
    $port = $req.Url.Port
    $hostOk = @("localhost:$port", "127.0.0.1:$port", "[::1]:$port") -contains [string]$req.Headers['Host']
    $originOk = (-not $origin) -or (@("http://localhost:$port", "http://127.0.0.1:$port", "http://[::1]:$port") -contains [string]$origin)
    # Loopback caller, loopback Host (blocks DNS rebinding), and Origin absent or same-origin (blocks other web pages).
    $ok = [System.Net.IPAddress]::IsLoopback($req.RemoteEndPoint.Address) -and $hostOk -and $originOk
    $status = 404; $body = ''; $handled = $null
    if (-not $ok) { $status = 403 }
    elseif ($local -eq $script:IdPath -and $req.HttpMethod -eq 'GET') {
        $status = 200; $handled = 'id'
        $body = (New-Object PSObject -Property ([ordered]@{ tool = $Tool; version = $Version; pid = $PID; path = $Path })) | ConvertTo-Json -Compress
    }
    elseif ($local -eq $script:ShutdownPath -and $req.HttpMethod -eq 'POST' -and $req.Headers['X-FleetHacker-Shutdown'] -eq '1') {
        $status = 202; $handled = 'shutdown'; $body = '{"stopping":true}'
    }
    else { $status = 405 }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $res.StatusCode = $status
    $res.ContentType = 'application/json; charset=utf-8'
    $res.Headers['Cache-Control'] = 'no-store'
    $res.ContentLength64 = $bytes.Length
    if ($bytes.Length -gt 0) { $res.OutputStream.Write($bytes, 0, $bytes.Length) }
    $res.Close()
    if (-not $handled) { return 'denied' }
    return $handled
}

# ===================================================================================================================
# Shared services: start a dependency on demand (Start-FleetService, Get-FleetServiceState, Stop-FleetServiceChild)
# ===================================================================================================================
<#
  The services a Fleet app may start for itself. One entry per service:
    FolderName      folder name looked for next to the caller and in %USERPROFILE%\Projects
    Marker          file (relative to the folder) that proves it is that service, and the script that is started
    Port            default loopback port (PORTS.md)
    Tool            the id it reports at GET /__fleethacker/id
    IdPathLeaf      when set, a reported id path must end with this (tells TalkForge's speech server from its page server)
    Exe             'powershell' (Windows PowerShell 5.1) or 'node' (Node.js on PATH)
    Arguments       {script} = full path of Marker, {port} = port, {idle} = IdleMinutes
    PortArgument    appended (with {port}) only when the port is not the default; '' when Arguments already carries it
    Launch          'shell': detached through the shell, hidden, inherits no handles, outlives the caller (its
                    environment cannot be set). 'child': a hidden child with stdout/stderr redirected and drained,
                    environment set from -Environment, the caller's secret-looking variables removed.
    OutlivesCaller  true for 'shell' services, false for 'child' services (documentation; Launch decides)
    StartSeconds    a start this recent is still "starting"; after it, an unanswered start is "unavailable"
    TrackPid        'child' only: the start has failed as soon as the started process exits
    RequiredEnvironment  names that -Environment must carry, with the minimum length of each value
    RemoveEnvironment    names always removed from a child's environment before -Environment is applied
#>
$script:FleetServices = @{
    'fairlead'  = @{
        DisplayName = 'Fairlead'; FolderName = 'Fairlead'; Marker = 'scripts\Start-Fairlead.ps1'; Port = 8776
        Tool = 'fairlead'; IdPathLeaf = ''; Exe = 'powershell'
        Arguments = '-STA -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{script}" --no-browser'
        PortArgument = '-Port {port}'; Launch = 'shell'; OutlivesCaller = $true; StartSeconds = 60; TrackPid = $false
        RequiredEnvironment = @{}; RemoveEnvironment = @(); IdleMinutes = 0
    }
    'talkforge' = @{
        DisplayName = 'TalkForge'; FolderName = 'TalkForge'; Marker = 'tools\talkforge.mjs'; Port = 25009
        Tool = 'talkforge'; IdPathLeaf = 'tools\talkforge.mjs'; Exe = 'node'
        Arguments = '"{script}" serve --port {port} --idle-timeout {idle}'
        PortArgument = ''; Launch = 'child'; OutlivesCaller = $false; StartSeconds = 45; TrackPid = $true
        RequiredEnvironment = @{ 'TALKFORGE_TOKEN' = 16 }; RemoveEnvironment = @('TALKFORGE_TOKEN', 'TALKFORGE_TOKEN_FILE', 'TALKFORGE_LAZARETTE_ITEM'); IdleMinutes = 30
    }
}
# Caller variables with names like these never reach a 'child' service (unless passed in -Environment).
$script:FleetSecretEnvPattern = '(?i)(TOKEN|SECRET|PASSWORD|PASSWD|PASSPHRASE|API_?KEY|_KEY$|CREDENTIAL)'
# Processes this caller started as 'child', keyed "<name>:<port>": kept so their output stays drained and so
# Stop-FleetServiceChild can end them. Nothing another app started is ever in here.
$script:FleetServiceChildren = [hashtable]::Synchronized(@{})

function Get-FleetServiceDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)
    $key = $Name.ToLowerInvariant()
    if (-not $script:FleetServices.ContainsKey($key)) { throw "Unknown Fleet service '$Name'. Known: $((@($script:FleetServices.Keys) | Sort-Object) -join ', ')." }
    $d = $script:FleetServices[$key].Clone()
    $d.Name = $key
    return $d
}

# The service folder: -Folder exactly when given (no fallback), else <sibling of the caller>\<FolderName>
# (the caller's folder and its parent are both tried, since entry scripts often live in server\ or src\),
# else %USERPROFILE%\Projects\<FolderName>. Returns @{ Folder; Problem }.
function Find-FleetServiceFolder {
    param($Definition, [string]$Folder, [string]$CallerRoot)
    $marker = $Definition.Marker
    if ($Folder) {
        if (Test-Path -LiteralPath (Join-Path $Folder $marker) -PathType Leaf) { return @{ Folder = (ConvertTo-FleetAbsolutePath $Folder); Problem = '' } }
        return @{ Folder = ''; Problem = "$($Definition.DisplayName) was not found in $Folder (no $marker there). Fix the configured folder, or start $($Definition.DisplayName) yourself." }
    }
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($CallerRoot) {
        $r = $CallerRoot
        for ($i = 0; $i -lt 2 -and $r; $i++) {
            $parent = Split-Path -Parent $r
            if ($parent) { $candidates.Add((Join-Path $parent $Definition.FolderName)) }
            $r = $parent
        }
    }
    if ($env:USERPROFILE) { $candidates.Add((Join-Path $env:USERPROFILE (Join-Path 'Projects' $Definition.FolderName))) }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $c $marker) -PathType Leaf) { return @{ Folder = (ConvertTo-FleetAbsolutePath $c); Problem = '' } }
    }
    return @{ Folder = ''; Problem = "$($Definition.DisplayName) was not found next to this app or in your Projects folder. Set its folder in the app's settings, or start $($Definition.DisplayName) yourself." }
}

# The script a node.exe command line runs (the first argument that is not an option), or $null.
# Refuses ($null) on options that run other code first (-e, -p, -r, --eval, --print, --require, --import, --loader).
function Get-FleetNodeScriptFromCommandLine {
    param([string]$CommandLine)
    [string[]]$argv = Split-FleetCommandLine $CommandLine
    if ($null -eq $argv -or $argv.Count -lt 2) { return $null }
    $exeLeaf = ($argv[0] -split '[\\/]')[-1].ToLowerInvariant()
    if (@('node', 'node.exe') -notcontains $exeLeaf) { return $null }
    for ($k = 1; $k -lt $argv.Count; $k++) {
        $a = $argv[$k]
        if ($a -match '^(?i)(-e|-p|-r|-pe|--eval|--print|--require|--import|--loader|--experimental-loader)(=|$)') { return $null }
        if ($a.StartsWith('-')) { continue }
        return $a
    }
    return $null
}

# PIDs listening on the port: Get-NetTCPConnection, or netstat.exe -ano when that cmdlet is missing.
function Get-FleetServicePortOwner {
    param([int]$Port)
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        return @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.OwningProcess } | Sort-Object -Unique)
    }
    $netstat = Join-Path ([Environment]::SystemDirectory) 'netstat.exe'
    if (-not (Test-Path -LiteralPath $netstat)) { return @() }
    $owners = @()
    foreach ($line in @(& $netstat -ano -p TCP 2>$null) + @(& $netstat -ano -p TCPv6 2>$null)) {
        if ([string]$line -match '^\s*TCP\s+(\S+):(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$' -and [int]$Matches[2] -eq $Port) { $owners += [int]$Matches[3] }
    }
    return @($owners | Sort-Object -Unique)
}

<#
  Is the program on the port this service? Returns @{ Ok; Id; Problem } (Problem 'none' when nothing FleetHacker answers).
  Ok only when GET /__fleethacker/id reports the service's tool id and a pid above 4 that owns the listening port, and,
  when it reports a path: that path is absolute, ends with IdPathLeaf when the service has one, and EXACTLY equals the
  pid's ExecutablePath, its PowerShell -File script or its node script (never a substring match).
#>
function Test-FleetServiceIdentity {
    param($Definition, [int]$Port, [int]$TimeoutMs = 1500,
        [scriptblock]$GetProcessInfo = { param($i) Get-FleetProcessInfo -ProcessId $i },
        [scriptblock]$GetPortOwner = { param($p) Get-FleetServicePortOwner -Port $p })
    $id = Test-FleetSelf -Port $Port -Tool $Definition.Tool -TimeoutMs $TimeoutMs
    if (-not $id) { return @{ Ok = $false; Id = $null; Problem = 'none' } }
    if (-not $id.IsSelf) { return @{ Ok = $false; Id = $id; Problem = "FleetHacker tool '$($id.Tool)'" } }
    $procId = [int]$id.Pid
    if ($procId -le 4) { return @{ Ok = $false; Id = $id; Problem = "a program that reports pid $procId" } }
    $owners = @(& $GetPortOwner $Port)
    if ($owners -notcontains $procId) { return @{ Ok = $false; Id = $id; Problem = "a program that says it is $($Definition.Tool) pid $procId, but the port is held by pid(s) '$($owners -join ', ')'" } }
    if ($id.Path) {
        $want = ConvertTo-FleetAbsolutePath $id.Path
        if (-not $want) { return @{ Ok = $false; Id = $id; Problem = "a program that reports a path that is not absolute ('$($id.Path)')" } }
        if ($Definition.IdPathLeaf -and -not $want.EndsWith('\' + $Definition.IdPathLeaf, [StringComparison]::OrdinalIgnoreCase)) {
            return @{ Ok = $false; Id = $id; Problem = "another $($Definition.DisplayName) program ($want), not the one this app needs" }
        }
        $info = & $GetProcessInfo $procId
        $match = $false
        if ($info) {
            $match = Test-FleetProcessIdentity -Path $want -CommandLine $info.CommandLine -ExecutablePath $info.ExecutablePath
            if (-not $match) {
                $nodeScript = ConvertTo-FleetAbsolutePath (Get-FleetNodeScriptFromCommandLine $info.CommandLine)
                $match = [bool]($nodeScript -and [string]::Equals($nodeScript, $want, [StringComparison]::OrdinalIgnoreCase))
            }
        }
        if (-not $match) { return @{ Ok = $false; Id = $id; Problem = "a program that says it is $($Definition.Tool) at $want, but pid $procId is not running that file" } }
    }
    return @{ Ok = $true; Id = $id; Problem = '' }
}

# ---- recent-start guard: a named mutex around the decision, and a small state file per service and port ----
function Get-FleetServiceStateDirectory {
    param([string]$StateDirectory)
    if ($StateDirectory) { return $StateDirectory }
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = [IO.Path]::GetTempPath() }
    return (Join-Path $base 'FleetHacker\services')
}

function Get-FleetServiceStartRecord {
    param([string]$Directory, [string]$Name, [int]$Port)
    $f = Join-Path $Directory ('{0}-{1}.json' -f $Name, $Port)
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return $null }
    try {
        $o = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $at = [datetime]::Parse([string]$o.startedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        return @{ StartedAt = $at.ToUniversalTime(); Pid = [int]$o.pid; Path = $f }
    } catch { return $null }
}

function Set-FleetServiceStartRecord {
    param([string]$Directory, [string]$Name, [int]$Port, [int]$ProcessId)
    if (-not (Test-Path -LiteralPath $Directory)) { [void](New-Item -ItemType Directory -Path $Directory -Force) }
    $f = Join-Path $Directory ('{0}-{1}.json' -f $Name, $Port)
    $json = (New-Object PSObject -Property ([ordered]@{ name = $Name; port = $Port; pid = $ProcessId; startedAt = [datetime]::UtcNow.ToString('o'); by = $PID })) | ConvertTo-Json -Compress
    $tmp = $f + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $f) { [IO.File]::Replace($tmp, $f, $null) } else { [IO.File]::Move($tmp, $f) }
}

function Clear-FleetServiceStartRecord {
    param([string]$Directory, [string]$Name, [int]$Port)
    Remove-Item -LiteralPath (Join-Path $Directory ('{0}-{1}.json' -f $Name, $Port)) -Force -ErrorAction SilentlyContinue
}

function Test-FleetProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    return [bool]($p -and -not $p.HasExited)
}

function New-FleetServiceResult {
    param([string]$State, [string]$Message, [bool]$StartedHere = $false, $Definition, [int]$Port, [string]$Reason = '', [int]$ProcessId = 0, [string]$Version = '', [string]$Folder = '')
    New-Object PSObject -Property ([ordered]@{
        State = $State; Message = $Message; StartedHere = $StartedHere; Name = $Definition.Name; Port = $Port
        Url = "http://127.0.0.1:$Port"; Pid = $ProcessId; Version = $Version; Folder = $Folder; Reason = $Reason })
}

<#
.SYNOPSIS
    The state of a shared service on its port. Starts nothing, stops nothing.
.DESCRIPTION
    State is one of:
      running      the port answers /__fleethacker/id as this service, and its pid and path check out
      starting     a start was recorded in the last StartSeconds (by any app) and it is not answering yet
      stopped      nothing listens and no start is in progress (Start-FleetService would start it)
      unavailable  the port is held by another program (Reason 'port-taken'), or a recent start failed
                   (Reason 'exited' or 'timeout'); Message says what to do
#>
function Get-FleetServiceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$Port = 0,
        [string]$StateDirectory = '',
        [int]$ProbeTimeoutMs = 1500
    )
    $d = Get-FleetServiceDefinition -Name $Name
    if ($Port -le 0) { $Port = [int]$d.Port }
    $dir = Get-FleetServiceStateDirectory $StateDirectory
    $rec = Get-FleetServiceStartRecord -Directory $dir -Name $d.Name -Port $Port
    $recent = $false
    if ($rec) { $recent = (([datetime]::UtcNow - $rec.StartedAt).TotalSeconds -lt [int]$d.StartSeconds) }
    $dn = $d.DisplayName
    if (-not (Test-FleetPortFree -Port $Port)) {
        $who = Test-FleetServiceIdentity -Definition $d -Port $Port -TimeoutMs $ProbeTimeoutMs
        if ($who.Ok) {
            if ($rec) { Clear-FleetServiceStartRecord -Directory $dir -Name $d.Name -Port $Port }
            return (New-FleetServiceResult 'running' "$dn is running." $false $d $Port '' ([int]$who.Id.Pid) ([string]$who.Id.Version))
        }
        # Just started: the port can be open a moment before the id answers.
        if ($recent -and $who.Problem -eq 'none') { return (New-FleetServiceResult 'starting' "$dn is starting." $false $d $Port 'starting' $rec.Pid) }
        $what = 'another program'
        if ($who.Problem -ne 'none') { $what = $who.Problem }
        return (New-FleetServiceResult 'unavailable' "Port $Port is in use by $what, so $dn was not started there. Close that program, or set $dn to another port." $false $d $Port 'port-taken')
    }
    if ($rec) {
        if ($d.TrackPid -and -not (Test-FleetProcessAlive $rec.Pid)) {
            Clear-FleetServiceStartRecord -Directory $dir -Name $d.Name -Port $Port
            return (New-FleetServiceResult 'unavailable' "$dn stopped while starting. Start it in a terminal to see why." $false $d $Port 'exited')
        }
        if ($recent) { return (New-FleetServiceResult 'starting' "$dn is starting." $false $d $Port 'starting' $rec.Pid) }
        Clear-FleetServiceStartRecord -Directory $dir -Name $d.Name -Port $Port
        return (New-FleetServiceResult 'unavailable' "$dn was started but did not answer on port $Port within $($d.StartSeconds) s. Start it yourself to see why." $false $d $Port 'timeout')
    }
    return (New-FleetServiceResult 'stopped' "$dn is not running." $false $d $Port 'not-running')
}

function Resolve-FleetServiceExe {
    param([string]$Exe)
    if ($Exe -eq 'powershell') {
        $p = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (Test-Path -LiteralPath $p) { return $p }
        return $null
    }
    $c = Get-Command "$Exe.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $c) { $c = Get-Command $Exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($c) { return [string]$c.Source }
    return $null
}

# The ProcessStartInfo that would run the service. Separate so the tests can check exactly what would run.
function New-FleetServiceStartInfo {
    param($Definition, [string]$ExePath, [string]$Folder, [int]$Port, [hashtable]$Environment = @{})
    $script = Join-Path $Folder $Definition.Marker
    $arguments = $Definition.Arguments.Replace('{script}', $script).Replace('{port}', [string]$Port).Replace('{idle}', [string]$Definition.IdleMinutes)
    if ($Definition.PortArgument -and $Port -ne [int]$Definition.Port) { $arguments += ' ' + $Definition.PortArgument.Replace('{port}', [string]$Port) }
    $si = New-Object Diagnostics.ProcessStartInfo
    $si.FileName = $ExePath
    $si.Arguments = $arguments
    $si.WorkingDirectory = $Folder
    $si.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    if ($Definition.Launch -eq 'shell') {
        # Through the shell: no handle of this process is inherited, so the service outlives the caller.
        $si.UseShellExecute = $true
        return $si
    }
    $si.UseShellExecute = $false
    $si.CreateNoWindow = $true
    # Read and dropped by the caller, never inherited: an inherited handle keeps the caller's console or pipe open.
    $si.RedirectStandardOutput = $true
    $si.RedirectStandardError = $true
    $si.RedirectStandardInput = $true
    foreach ($n in @($si.EnvironmentVariables.Keys | ForEach-Object { [string]$_ })) {
        if (($Definition.RemoveEnvironment -contains $n) -or ($n -match $script:FleetSecretEnvPattern)) { $si.EnvironmentVariables.Remove($n) }
    }
    foreach ($k in $Environment.Keys) { $si.EnvironmentVariables[[string]$k] = [string]$Environment[$k] }
    return $si
}

<#
.SYNOPSIS
    Makes sure a shared service (fairlead, talkforge) is running: reuses a verified one, otherwise starts it once.
.DESCRIPTION
    Probes the port and /__fleethacker/id (tool, pid owns the listener, path matches the process when reported).
    Never starts on a port another program holds, and never starts twice: the decision is taken under a named mutex
    (Local\FleetHacker.FleetService.<name>.<port>) and a start is recorded in <StateDirectory>\<name>-<port>.json, which
    every app and runspace reads, so a start in the last StartSeconds is reported as 'starting' instead of repeated.
    Fairlead ('shell') starts detached and hidden through the shell and outlives the caller. TalkForge ('child') starts
    as a hidden child with its output drained, the token only in its environment (never on its command line), and the
    caller's secret-looking variables removed; Stop-FleetServiceChild ends it.
    Returns @{ State = running|starting|unavailable; Message; StartedHere; Name; Port; Url; Pid; Version; Folder; Reason }.
    Expected failures do not throw; Message is a sentence for the person.
.EXAMPLE
    $r = Start-FleetService -Name talkforge -Environment @{ TALKFORGE_TOKEN = $token } -WaitSeconds 20
    $token = $null
    if ($r.State -ne 'running') { Write-Log $r.Message }
#>
function Start-FleetService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Folder = '',
        [int]$Port = 0,
        [hashtable]$Environment = @{},
        [int]$WaitSeconds = 0,
        [string]$CallerRoot = '',
        [string]$StateDirectory = '',
        [int]$ProbeTimeoutMs = 1500,
        [int]$MutexWaitSeconds = 30
    )
    $d = Get-FleetServiceDefinition -Name $Name
    if ($Port -le 0) { $Port = [int]$d.Port }
    if (-not $CallerRoot) { $CallerRoot = [string]$MyInvocation.PSScriptRoot }
    $dir = Get-FleetServiceStateDirectory $StateDirectory
    $dn = $d.DisplayName
    $no = { param($msg, $why) New-FleetServiceResult 'unavailable' $msg $false $d $Port $why }

    $mutex = New-Object System.Threading.Mutex($false, ('Local\FleetHacker.FleetService.{0}.{1}' -f $d.Name, $Port))
    $held = $false
    $result = $null
    try {
        try { $held = $mutex.WaitOne([TimeSpan]::FromSeconds($MutexWaitSeconds)) }
        catch [System.Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { return (& $no "Another app is still deciding whether to start $dn. Try again in a moment." 'busy') }

        $now = Get-FleetServiceState -Name $d.Name -Port $Port -StateDirectory $dir -ProbeTimeoutMs $ProbeTimeoutMs
        if ($now.State -ne 'stopped') { $result = $now }
        else {
            if ($d.Launch -eq 'shell' -and $Environment.Count -gt 0) { return (& $no "$dn is started through the shell, which cannot set its environment; pass no -Environment." 'bad-call') }
            foreach ($req in $d.RequiredEnvironment.Keys) {
                $v = $null; if ($Environment.ContainsKey($req)) { $v = [string]$Environment[$req] }
                if (-not $v -or $v.Length -lt [int]$d.RequiredEnvironment[$req]) {
                    $v = $null
                    return (& $no "$dn needs $req (at least $($d.RequiredEnvironment[$req]) characters) to start. Check the item that holds it." 'no-secret')
                }
                $v = $null
            }
            $found = Find-FleetServiceFolder -Definition $d -Folder $Folder -CallerRoot $CallerRoot
            if (-not $found.Folder) { return (& $no $found.Problem 'not-found') }
            $exe = Resolve-FleetServiceExe $d.Exe
            if (-not $exe) {
                $need = 'Windows PowerShell 5.1'; if ($d.Exe -eq 'node') { $need = 'Node.js 18 or newer' }
                return (& $no "$dn needs $need, and it was not found on this computer." 'no-runtime')
            }
            $si = $null; $p = $null
            try {
                $si = New-FleetServiceStartInfo -Definition $d -ExePath $exe -Folder $found.Folder -Port $Port -Environment $Environment
                $p = [Diagnostics.Process]::Start($si)
                $childPid = 0; if ($p) { $childPid = $p.Id }
                if ($d.Launch -eq 'child') {
                    $p.BeginOutputReadLine(); $p.BeginErrorReadLine()   # drained with no handler: the lines are dropped
                    try { $p.StandardInput.Close() } catch { }
                    $key = "$($d.Name):$Port"
                    $old = $script:FleetServiceChildren[$key]
                    if ($old) { try { $old.Dispose() } catch { } }
                    $script:FleetServiceChildren[$key] = $p
                } elseif ($p) { $p.Dispose() }
                Set-FleetServiceStartRecord -Directory $dir -Name $d.Name -Port $Port -ProcessId $childPid
                $result = New-FleetServiceResult 'starting' "$dn is starting." $true $d $Port 'starting' $childPid '' $found.Folder
            } catch {
                return (& $no "$dn could not be started ($($_.Exception.GetType().Name)). Start it yourself to see why." 'start-failed')
            } finally {
                # The values were copied into the child at start; drop this copy.
                if ($si -and -not $si.UseShellExecute) { foreach ($k in @($Environment.Keys)) { try { $si.EnvironmentVariables.Remove([string]$k) } catch { } } }
                $si = $null
            }
        }
    } finally {
        if ($held) { try { $mutex.ReleaseMutex() } catch { } }
        $mutex.Dispose()
    }

    if ($WaitSeconds -gt 0 -and $result.State -eq 'starting') {
        $startedHere = $result.StartedHere; $folderUsed = $result.Folder
        $sw = [Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Milliseconds 250
            $result = Get-FleetServiceState -Name $d.Name -Port $Port -StateDirectory $dir -ProbeTimeoutMs $ProbeTimeoutMs
        } while ($result.State -eq 'starting' -and $sw.Elapsed.TotalSeconds -lt $WaitSeconds)
        $result.StartedHere = $startedHere
        if (-not $result.Folder) { $result.Folder = $folderUsed }
        if ($result.State -eq 'starting') { $result.Message = "$dn is still starting after $WaitSeconds s." }
    }
    return $result
}

<#
.SYNOPSIS
    Stops a 'child' service (TalkForge) that THIS process started with Start-FleetService. A service started by another
    app, by hand, or through the shell (Fairlead) is never touched. Returns $true when it stopped one.
#>
function Stop-FleetServiceChild {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name, [int]$Port = 0, [string]$StateDirectory = '')
    $d = Get-FleetServiceDefinition -Name $Name
    if ($Port -le 0) { $Port = [int]$d.Port }
    $key = "$($d.Name):$Port"
    $p = $script:FleetServiceChildren[$key]
    $script:FleetServiceChildren.Remove($key)
    if (-not $p) { return $false }
    $dir = Get-FleetServiceStateDirectory $StateDirectory
    try {
        if ($p.HasExited) { return $false }
        $childPid = $p.Id
        $p.Kill()
        [void]$p.WaitForExit(5000)
        $rec = Get-FleetServiceStartRecord -Directory $dir -Name $d.Name -Port $Port
        if ($rec -and $rec.Pid -eq $childPid) { Clear-FleetServiceStartRecord -Directory $dir -Name $d.Name -Port $Port }
        return $true
    } catch { return $false } finally { try { $p.Dispose() } catch { } }
}

Export-ModuleMember -Function Get-FleetPortBlock, Test-FleetPortFree, Test-FleetSelf, Stop-FleetInstance, Resolve-FleetPort, Invoke-FleetIdEndpoint,
    Get-FleetServiceDefinition, Get-FleetServiceState, Start-FleetService, Stop-FleetServiceChild
