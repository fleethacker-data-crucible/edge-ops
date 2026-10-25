<#
.SYNOPSIS
  Loopback port selection for FleetHacker tools (Windows PowerShell 5.1). ASCII only.
.DESCRIPTION
  Follows phoenix-lai (src\WebServer.cs StartOnFreePort) and data-noodler (server\server.ps1):
  - an HttpListener with ONE prefix, http://127.0.0.1:<port>/ (never +, *, 0.0.0.0, or localhost);
  - try the tool's preferred port (settings.json or -Port), then scan the tool's range from PORTS.md;
  - a port that is taken throws HttpListenerException; move to the next one;
  - keep the started listener (no probe-then-bind race) and report the port you actually got.
  No admin rights: no URL ACL, no netsh, no firewall change.
  Dot-source it: . (Join-Path $PSScriptRoot 'LoopbackPort.ps1')
#>

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
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://127.0.0.1:$p/")
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

# Reject anything whose Host header is not this listener (DNS-rebinding guard, as in both repos).
function Test-LocalRequest {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][int]$Port)
    return ($Request.Headers['Host'] -eq "127.0.0.1:$Port")
}
