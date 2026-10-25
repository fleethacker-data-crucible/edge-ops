<#
.SYNOPSIS
    FleetHacker test-isolation harness: isolated Chrome instances and cross-process resource leases.
.DESCRIPTION
    Windows PowerShell 5.1 compatible. Set-StrictMode -Version Latest safe.
    Chrome:  Start-IsolatedChrome / Stop-IsolatedChrome
    Leases:  Enter-FleetLock / Update-FleetLock / Exit-FleetLock / Get-FleetLocks
             Start-FleetLockHeartbeat / Stop-FleetLockHeartbeat
#>
Set-StrictMode -Version Latest

$script:LockRoot = if ($env:FLEET_LOCK_ROOT) { $env:FLEET_LOCK_ROOT } else { Join-Path $env:ProgramData 'fleethacker\locks' }
$script:StaleSeconds = 300
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-FleetUtcNow { [DateTime]::UtcNow.ToString('o') }

function Get-FleetLockPath {
    param([Parameter(Mandatory)][string]$Resource)
    if ($Resource -notmatch '^[A-Za-z0-9._-]+$') { throw "Invalid resource name '$Resource' (use letters, digits, . _ -)" }
    if (-not (Test-Path -LiteralPath $script:LockRoot)) { New-Item -ItemType Directory -Path $script:LockRoot -Force | Out-Null }
    Join-Path $script:LockRoot ($Resource + '.json')
}

function Read-FleetLockFile {
    param([string]$Path)
    try {
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        try { $sr = New-Object IO.StreamReader($fs); $txt = $sr.ReadToEnd() } finally { $fs.Dispose() }
        if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
        return ($txt | ConvertFrom-Json)
    } catch { return $null }
}

function Test-FleetLockStale {
    <#
    .SYNOPSIS
        Returns $true if a lock record is stale (heartbeat older than 5 min, or owner PID dead on this host).
    #>
    param($Record, [string]$Path)
    if ($null -eq $Record) {
        # Unreadable/empty file: stale only if file itself is old (a writer may be mid-create).
        if ($Path -and (Test-Path -LiteralPath $Path)) {
            return (((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds -gt $script:StaleSeconds)
        }
        return $false
    }
    $hb = [DateTime]::MinValue
    try { $hb = [DateTime]::Parse([string]$Record.heartbeat, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() } catch { return $true }
    if (([DateTime]::UtcNow - $hb).TotalSeconds -gt $script:StaleSeconds) { return $true }
    if ([string]$Record.host -eq $env:COMPUTERNAME) {
        $p = Get-Process -Id ([int]$Record.pid) -ErrorAction SilentlyContinue
        if ($null -eq $p) { return $true }
    }
    return $false
}

function Write-FleetLockNew {
    param([string]$Path, [hashtable]$Data)
    $json = ($Data | ConvertTo-Json -Compress)
    $bytes = $script:Utf8NoBom.GetBytes($json)
    $fs = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush() } finally { $fs.Dispose() }
}

function Enter-FleetLock {
    <#
    .SYNOPSIS
        Acquires a named cross-process lease (atomic CreateNew), waiting up to -TimeoutSec.
    .DESCRIPTION
        Lock file: C:\ProgramData\fleethacker\locks\<Resource>.json with owner, pid, host, acquired, heartbeat (ISO 8601 UTC), token.
        Stale locks (heartbeat > 5 min, or owner PID dead on this host) are taken over safely:
        a short-lived <Resource>.takeover guard file serializes takers; the stale file is renamed to a unique tombstone,
        then a new file is created with CreateNew, so only one taker can win.
    .PARAMETER Resource
        e.g. desktop-focus, outlook-com, gpu, port-8771
    .PARAMETER Owner
        Free-text owner id, e.g. "<agent>/<runid>". Defaults to user@host:pid.
    .PARAMETER TimeoutSec
        Seconds to wait. 0 = single attempt.
    .PARAMETER OwnerPid
        PID recorded as the owner (default: current process).
    .PARAMETER Heartbeat
        Also start a background heartbeat (every 30 s) tied to OwnerPid.
    .OUTPUTS
        Lock handle object (Resource, Path, Token, Owner, Pid, ...). Throws TimeoutException on timeout.
    .EXAMPLE
        $l = Enter-FleetLock desktop-focus -TimeoutSec 120 -Heartbeat; try { ... } finally { Exit-FleetLock $l }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Resource,
        [string]$Owner = ("{0}@{1}:{2}" -f $env:USERNAME, $env:COMPUTERNAME, $PID),
        [int]$TimeoutSec = 0,
        [int]$OwnerPid = $PID,
        [int]$PollMs = 500,
        [switch]$Heartbeat
    )
    $path = Get-FleetLockPath $Resource
    $guard = $path -replace '\.json$', '.takeover'
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $token = [guid]::NewGuid().ToString('N')
    while ($true) {
        $now = Get-FleetUtcNow
        $data = @{ resource = $Resource; owner = $Owner; pid = $OwnerPid; host = $env:COMPUTERNAME; acquired = $now; heartbeat = $now; token = $token }
        $won = $false
        try { Write-FleetLockNew -Path $path -Data $data; $won = $true } catch [System.IO.IOException] { $won = $false }
        if (-not $won) {
            $rec = Read-FleetLockFile $path
            if (Test-FleetLockStale -Record $rec -Path $path) {
                # Clear an abandoned guard (> 30 s old)
                if ((Test-Path -LiteralPath $guard) -and (((Get-Date) - (Get-Item -LiteralPath $guard -ErrorAction SilentlyContinue).LastWriteTime).TotalSeconds -gt 30)) {
                    Remove-Item -LiteralPath $guard -Force -ErrorAction SilentlyContinue
                }
                $haveGuard = $false
                try { Write-FleetLockNew -Path $guard -Data @{ token = $token; pid = $PID }; $haveGuard = $true } catch [System.IO.IOException] { }
                if ($haveGuard) {
                    try {
                        $rec2 = Read-FleetLockFile $path
                        if ((Test-Path -LiteralPath $path) -and (Test-FleetLockStale -Record $rec2 -Path $path)) {
                            $tomb = '{0}.stale-{1}-{2}' -f $path, ([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')), $token
                            try { [IO.File]::Move($path, $tomb) } catch { }
                            Write-Verbose "Took over stale lock $Resource (previous owner: $(if($rec2){$rec2.owner}else{'unreadable'}))"
                        }
                        try { Write-FleetLockNew -Path $path -Data $data; $won = $true } catch [System.IO.IOException] { $won = $false }
                    } finally { Remove-Item -LiteralPath $guard -Force -ErrorAction SilentlyContinue }
                }
            }
        }
        if ($won) {
            $h = [pscustomobject]@{ Resource = $Resource; Path = $path; Token = $token; Owner = $Owner; Pid = $OwnerPid; Host = $env:COMPUTERNAME; Acquired = $now; HeartbeatJob = $null }
            if ($Heartbeat) { Start-FleetLockHeartbeat -Lock $h | Out-Null }
            return $h
        }
        if ((Get-Date) -ge $deadline) {
            $cur = Read-FleetLockFile $path
            $who = if ($cur) { "$($cur.owner) (pid $($cur.pid))" } else { 'unknown' }
            throw (New-Object System.TimeoutException("Timed out after $TimeoutSec s waiting for lock '$Resource' held by $who"))
        }
        Start-Sleep -Milliseconds $PollMs
    }
}

function Update-FleetLock {
    <#
    .SYNOPSIS
        Renews (heartbeats) a lease you own. Returns $true on success, $false if you no longer own it.
    .PARAMETER Lock
        Handle returned by Enter-FleetLock (or any object with Path and Token).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)]$Lock)
    $rec = Read-FleetLockFile $Lock.Path
    if ($null -eq $rec -or [string]$rec.token -ne [string]$Lock.Token) { return $false }
    $data = @{ resource = $rec.resource; owner = $rec.owner; pid = $rec.pid; host = $rec.host; acquired = $rec.acquired; heartbeat = (Get-FleetUtcNow); token = $rec.token }
    $tmp = '{0}.hb-{1}' -f $Lock.Path, [guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($tmp, ($data | ConvertTo-Json -Compress), $script:Utf8NoBom)
    try { [IO.File]::Replace($tmp, $Lock.Path, [NullString]::Value); return $true }
    catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; return $false }
}

function Exit-FleetLock {
    <#
    .SYNOPSIS
        Releases a lease after verifying ownership (token match). Stops its heartbeat job. Returns $true if released.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)]$Lock)
    Stop-FleetLockHeartbeat -Lock $Lock
    $rec = Read-FleetLockFile $Lock.Path
    if ($null -eq $rec -or [string]$rec.token -ne [string]$Lock.Token) {
        Write-Warning "Lock '$($Lock.Resource)' is not owned by this handle; not releasing."
        return $false
    }
    $tomb = '{0}.rel-{1}' -f $Lock.Path, $Lock.Token
    try { [IO.File]::Move($Lock.Path, $tomb) } catch { return $false }
    $check = Read-FleetLockFile $tomb
    if ($check -and [string]$check.token -ne [string]$Lock.Token) {
        try { [IO.File]::Move($tomb, $Lock.Path) } catch { }
        return $false
    }
    Remove-Item -LiteralPath $tomb -Force -ErrorAction SilentlyContinue
    return $true
}

function Start-FleetLockHeartbeat {
    <#
    .SYNOPSIS
        Starts a background job that renews the lease every -IntervalSec (default 30) while the owner PID is alive.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Lock, [int]$IntervalSec = 30)
    $mod = $PSCommandPath
    if (-not $mod) { $mod = Join-Path $PSScriptRoot 'FleetTestHarness.psm1' }
    $job = Start-Job -Name ("fleetlock-hb-" + $Lock.Resource) -ArgumentList $mod, $Lock.Path, $Lock.Token, $Lock.Pid, $IntervalSec -ScriptBlock {
        param($mod, $path, $token, $ownerPid, $interval)
        Import-Module $mod -Force
        $h = [pscustomobject]@{ Path = $path; Token = $token }
        while ($true) {
            Start-Sleep -Seconds $interval
            if (-not (Get-Process -Id $ownerPid -ErrorAction SilentlyContinue)) { break }
            if (-not (Update-FleetLock -Lock $h)) { break }
        }
    }
    $Lock.HeartbeatJob = $job
    return $job
}

function Stop-FleetLockHeartbeat {
    <# .SYNOPSIS Stops the heartbeat job attached to a lock handle, if any. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Lock)
    $j = $null
    if ($Lock.PSObject.Properties['HeartbeatJob']) { $j = $Lock.HeartbeatJob }
    if ($j) { Stop-Job $j -ErrorAction SilentlyContinue; Remove-Job $j -Force -ErrorAction SilentlyContinue; $Lock.HeartbeatJob = $null }
}

function Get-FleetLocks {
    <#
    .SYNOPSIS
        Lists current leases with an IsStale column.
    .EXAMPLE
        Get-FleetLocks | Format-Table
    #>
    [CmdletBinding()]
    param()
    if (-not (Test-Path -LiteralPath $script:LockRoot)) { return }
    Get-ChildItem -LiteralPath $script:LockRoot -Filter '*.json' -File | ForEach-Object {
        $r = Read-FleetLockFile $_.FullName
        $age = $null
        if ($r) { try { $age = [int]([DateTime]::UtcNow - [DateTime]::Parse([string]$r.heartbeat, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()).TotalSeconds } catch { } }
        [pscustomobject]@{
            Resource = $_.BaseName
            Owner = if ($r) { $r.owner } else { '<unreadable>' }
            Pid = if ($r) { $r.pid } else { $null }
            Host = if ($r) { $r.host } else { $null }
            Acquired = if ($r) { $r.acquired } else { $null }
            Heartbeat = if ($r) { $r.heartbeat } else { $null }
            HeartbeatAgeSec = $age
            IsStale = (Test-FleetLockStale -Record $r -Path $_.FullName)
        }
    }
}

# ---------------- Isolated Chrome ----------------

function Test-FleetPortFree {
    <# .SYNOPSIS True if 127.0.0.1:<Port> can be bound and no TCP connection/listener uses it. #>
    param([int]$Port)
    try {
        $c = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        if ($c) { return $false }
    } catch { }
    $l = $null
    try {
        $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
        $l.ExclusiveAddressUse = $true
        $l.Start(); return $true
    } catch { return $false } finally { if ($l) { $l.Stop() } }
}

function Start-IsolatedChrome {
    <#
    .SYNOPSIS
        Launches Chrome with a fresh profile and a unique, verified-free remote-debugging port (9300-9399).
    .DESCRIPTION
        Profile: %LOCALAPPDATA%\fleethacker\chrome\<Agent>-<RunId>. The candidate port is leased (port-<n>) during launch
        to avoid races with concurrent callers; the lease is released once Chrome owns the port.
        Waits until http://127.0.0.1:<port>/json/version responds.
    .PARAMETER Agent
        Short agent/job name (letters, digits, - _).
    .PARAMETER RunId
        Unique run id (default: timestamp + random).
    .PARAMETER Headless
        Adds --headless=new.
    .PARAMETER Url
        Optional URL to open.
    .PARAMETER ExtraArgs
        Additional Chrome arguments.
    .OUTPUTS
        [pscustomobject] Pid, Port, ProfilePath, Agent, RunId, DevToolsUrl, Browser
    .EXAMPLE
        $c = Start-IsolatedChrome -Agent uikit -Headless -Url 'file:///D:/x/demo.html'; try { ... } finally { Stop-IsolatedChrome $c }
    #>
    [CmdletBinding()]
    param(
        [string]$Agent = 'agent',
        [string]$RunId = ((Get-Date).ToString('yyyyMMddHHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 6))),
        [switch]$Headless,
        [string]$Url,
        [string[]]$ExtraArgs = @(),
        [int]$PortMin = 9300,
        [int]$PortMax = 9399,
        [int]$StartupTimeoutSec = 30,
        [string]$ChromePath = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
    )
    if ($Agent -notmatch '^[A-Za-z0-9_-]+$' -or $RunId -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Agent/RunId may only contain letters, digits, - _ .' }
    if (-not (Test-Path -LiteralPath $ChromePath)) { throw "Chrome not found at $ChromePath" }
    $root = Join-Path $env:LOCALAPPDATA 'fleethacker\chrome'
    $profilePath = Join-Path $root ("{0}-{1}" -f $Agent, $RunId)
    if (Test-Path -LiteralPath $profilePath) { throw "Profile path already exists: $profilePath" }
    New-Item -ItemType Directory -Path $profilePath -Force | Out-Null

    $ports = $PortMin..$PortMax | Sort-Object { Get-Random }
    foreach ($port in $ports) {
        $lease = $null
        try { $lease = Enter-FleetLock -Resource ("port-{0}" -f $port) -Owner ("chrome:{0}-{1}" -f $Agent, $RunId) -TimeoutSec 0 } catch { continue }
        try {
            if (-not (Test-FleetPortFree $port)) { continue }
            $chromeArgs = @("--user-data-dir=`"$profilePath`"", "--remote-debugging-port=$port", '--remote-debugging-address=127.0.0.1',
                      '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--disable-sync')
            if ($Headless) { $chromeArgs += '--headless=new' }
            if ($ExtraArgs) { $chromeArgs += $ExtraArgs }
            $chromeArgs += $(if ($Url) { $Url } else { 'about:blank' })
            $proc = Start-Process -FilePath $ChromePath -ArgumentList $chromeArgs -PassThru
            $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
            $ver = $null
            while ((Get-Date) -lt $deadline) {
                try { $ver = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/json/version" -f $port) -TimeoutSec 2 -UseBasicParsing; break } catch { Start-Sleep -Milliseconds 300 }
            }
            if ($null -eq $ver) {
                Stop-IsolatedChrome -Instance ([pscustomobject]@{ Pid = $proc.Id; ProfilePath = $profilePath }) -KeepProfile | Out-Null
                Write-Verbose "Chrome did not answer on port $port; trying another port"
                continue
            }
            # Resolve the browser PID actually listening (Start-Process PID may be a launcher).
            $chromePid = $proc.Id
            try { $own = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop | Select-Object -First 1; if ($own) { $chromePid = [int]$own.OwningProcess } } catch { }
            return [pscustomobject]@{ Pid = $chromePid; Port = $port; ProfilePath = $profilePath; Agent = $Agent; RunId = $RunId
                                      DevToolsUrl = [string]$ver.webSocketDebuggerUrl; Browser = [string]$ver.Browser }
        } finally { if ($lease) { Exit-FleetLock $lease | Out-Null } }
    }
    Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction SilentlyContinue
    throw "No free port in $PortMin-$PortMax could be used for Chrome"
}

function Stop-IsolatedChrome {
    <#
    .SYNOPSIS
        Kills only chrome.exe processes whose command line contains the instance's user-data-dir, then deletes the profile (with retries).
    .PARAMETER Instance
        Object returned by Start-IsolatedChrome (needs ProfilePath).
    .PARAMETER KeepProfile
        Do not delete the profile folder.
    .OUTPUTS
        [pscustomobject] Killed (PIDs), ProfileDeleted
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0, ValueFromPipeline)]$Instance, [switch]$KeepProfile, [int]$Retries = 20)
    process {
        $prof = [string]$Instance.ProfilePath
        if ([string]::IsNullOrWhiteSpace($prof) -or $prof -notlike '*\fleethacker\chrome\*') { throw "Refusing: '$prof' is not a harness profile path" }
        $killed = @()
        for ($i = 0; $i -lt 5; $i++) {
            $procs = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($prof, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
            if ($procs.Count -eq 0) { break }
            foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue; $killed += [int]$p.ProcessId }
            Start-Sleep -Milliseconds 500
        }
        $deleted = $false
        if (-not $KeepProfile) {
            for ($i = 0; $i -lt $Retries; $i++) {
                Remove-Item -LiteralPath $prof -Recurse -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path -LiteralPath $prof)) { $deleted = $true; break }
                Start-Sleep -Milliseconds 500
            }
        }
        [pscustomobject]@{ Killed = @($killed | Select-Object -Unique); ProfileDeleted = $deleted; ProfilePath = $prof }
    }
}

New-Alias -Name Acquire-FleetLock -Value Enter-FleetLock -Force
New-Alias -Name Renew-FleetLock -Value Update-FleetLock -Force
New-Alias -Name Release-FleetLock -Value Exit-FleetLock -Force
Export-ModuleMember -Function Enter-FleetLock, Update-FleetLock, Exit-FleetLock, Get-FleetLocks, Test-FleetLockStale, Start-FleetLockHeartbeat, Stop-FleetLockHeartbeat, Start-IsolatedChrome, Stop-IsolatedChrome, Test-FleetPortFree -Alias Acquire-FleetLock, Renew-FleetLock, Release-FleetLock
