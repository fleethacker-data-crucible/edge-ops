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
    held, Stop-Process only on the self-reported pid, and only after its command line / path matches the
    self-reported path.
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

# Graceful first (shutdown endpoint), then Stop-Process on the self-reported pid only if its
# command line or executable path contains the self-reported path. Returns $true once the port is free.
function Stop-FleetInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Instance,
        [int]$GraceMs = 5000,
        [switch]$NoForce
    )
    [void](Invoke-FleetLocalRequest -Port $Instance.Port -Path $script:ShutdownPath -Method 'POST' -Headers @{ 'X-FleetHacker-Shutdown' = '1' })
    if (Wait-FleetPortFree -Port $Instance.Port -TimeoutMs $GraceMs) { return $true }
    if ($NoForce -or -not $Instance.Pid -or -not $Instance.Path) { return $false }
    if ($Instance.Pid -eq $PID) { return $false }
    $p = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$Instance.Pid)" -ErrorAction SilentlyContinue
    if (-not $p) { return (Wait-FleetPortFree -Port $Instance.Port -TimeoutMs 1000) }
    $cmd = [string]$p.CommandLine; $exe = [string]$p.ExecutablePath
    $match = ($cmd.IndexOf($Instance.Path, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($exe -ieq $Instance.Path)
    if (-not $match) { Write-Warning "PID $($Instance.Pid) does not match '$($Instance.Path)'; not stopping it."; return $false }
    Stop-Process -Id $Instance.Pid -Force -ErrorAction SilentlyContinue
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

Export-ModuleMember -Function Get-FleetPortBlock, Test-FleetPortFree, Test-FleetSelf, Stop-FleetInstance, Resolve-FleetPort, Invoke-FleetIdEndpoint
