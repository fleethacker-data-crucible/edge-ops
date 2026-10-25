<#
.SYNOPSIS
  Loopback port selection for FleetHacker tools (Windows PowerShell 5.1). ASCII only.
.DESCRIPTION
  Follows phoenix-lai (src\WebServer.cs StartOnFreePort) and data-noodler (server\server.ps1):
  - HttpListener on http://localhost:<port>/ (or TcpListener on IPAddress.Loopback), never + / * / 0.0.0.0;
  - a port counts as free only if BOTH IPv4 (127.0.0.1) and IPv6 (::1) loopback are free;
  - try the tool's preferred port (settings.json or -Port), then scan the tool's range from PORTS.md;
  - a port that is taken throws HttpListenerException; move to the next one;
  - keep the started listener (no probe-then-bind race) and report the port you actually got.
  No admin rights: no URL ACL, no netsh, no firewall change.
  Dot-source it: . (Join-Path $PSScriptRoot 'LoopbackPort.ps1')
#>

# Free on both IPv4 and IPv6 loopback (localhost can resolve to either). No admin needed.
function Test-LoopbackPortFree {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)][int]$Port)
    foreach ($addr in @([System.Net.IPAddress]::Loopback, [System.Net.IPAddress]::IPv6Loopback)) {
        $t = New-Object System.Net.Sockets.TcpListener $addr, $Port
        try { $t.Start(); $t.Stop() }
        catch [System.Net.Sockets.SocketException] {
            # No IPv6 on this machine is not "busy".
            if ($addr.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6 -and
                $_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::AddressFamilyNotSupported) { continue }
            return $false
        }
    }
    return $true
}

function Start-LoopbackListener {
    [CmdletBinding()]
    [OutputType([System.Net.HttpListener])]
    param(
        [ValidateRange(1024, 65535)][int]$PreferredPort = 8771,
        [ValidateRange(1024, 65535)][int]$RangeStart = 8771,
        [ValidateRange(1024, 65535)][int]$RangeEnd = 8779
    )
    $candidates = @($PreferredPort) + @($RangeStart..$RangeEnd | Where-Object { $_ -ne $PreferredPort })
    foreach ($p in $candidates) {
        if (-not (Test-LoopbackPortFree -Port $p)) { continue }
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://localhost:$p/")
        try {
            $l.Start()
            return $l
        } catch [System.Net.HttpListenerException] {
            $l.Close()
        } catch {
            $l.Close()
            if ($_.Exception.InnerException -isnot [System.Net.HttpListenerException]) { throw }
        }
    }
    throw "No free local port: tried $PreferredPort and $RangeStart-$RangeEnd."
}

function Get-ListenerPort {
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory = $true)][System.Net.HttpListener]$Listener)
    $prefix = @($Listener.Prefixes)[0]
    return ([Uri]$prefix).Port
}

function Get-ListenerHost {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][System.Net.HttpListener]$Listener)
    return ([Uri](@($Listener.Prefixes)[0])).Host
}

# Request check, following keystone Test-KeystoneWebRequest: caller is loopback, Host and Origin match.
function Test-LocalRequest {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][int]$Port)
    if (-not [System.Net.IPAddress]::IsLoopback($Request.RemoteEndPoint.Address)) { return $false }
    $hostOk = @("localhost:$Port", "127.0.0.1:$Port", "[::1]:$Port") -contains $Request.Headers['Host']
    if (-not $hostOk) { return $false }
    $origin = $Request.Headers['Origin']
    if ($origin -and (@("http://localhost:$Port", "http://127.0.0.1:$Port") -notcontains $origin)) { return $false }
    return $true
}
