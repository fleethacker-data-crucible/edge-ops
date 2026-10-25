<#
.SYNOPSIS
  Reusable loopback port selection for FleetHacker tools (Windows PowerShell 5.1).
.DESCRIPTION
  Modeled on SnipHero's SnipHero.Transport.Server (modules/LocalHttp.ps1):
  - binds ONLY to 127.0.0.1 (IPAddress.Loopback), never + or *;
  - tries the preferred port, then the next ports in sequence;
  - moves on only for AddressAlreadyInUse / AccessDenied / AddressNotAvailable;
  - finally lets the OS assign a free port (bind to 0);
  - returns the started listener, so the socket is held from selection to
    shutdown (no check-then-bind race). Never stops another process.
  No Add-Type, no HttpListener URL ACL, no admin rights.
  Dot-source it: . "$PSScriptRoot\LoopbackPort.ps1"
#>
Set-StrictMode -Version 2.0

function New-LoopbackListener {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Opens a loopback socket only; no system state change.')]
    [CmdletBinding()]
    [OutputType([System.Net.Sockets.TcpListener])]
    param(
        [ValidateRange(1024, 65535)][int]$PreferredPort = 8771,
        [ValidateRange(1, 500)][int]$ScanCount = 20,
        [int]$Backlog = 32
    )
    $retryable = @(
        [System.Net.Sockets.SocketError]::AddressAlreadyInUse,
        [System.Net.Sockets.SocketError]::AccessDenied,
        [System.Net.Sockets.SocketError]::AddressNotAvailable
    )
    $last = $null
    for ($i = 0; $i -lt $ScanCount; $i++) {
        $port = $PreferredPort + $i
        if ($port -gt 65535) { $port = 1024 + ($port - 65536) }
        $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), $port
        try {
            $listener.Start($Backlog)
            return $listener
        } catch [System.Net.Sockets.SocketException] {
            $last = $_.Exception
            $listener.Stop()
            if ($retryable -notcontains $last.SocketErrorCode) { throw }
        } catch {
            $inner = $_.Exception.InnerException
            $listener.Stop()
            if ($inner -is [System.Net.Sockets.SocketException] -and $retryable -contains $inner.SocketErrorCode) {
                $last = $inner
                continue
            }
            throw
        }
    }
    $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), 0
    try {
        $listener.Start($Backlog)
        return $listener
    } catch {
        throw (New-Object System.InvalidOperationException ('Unable to bind a loopback TCP listener. Check workstation restrictions and localhost access.', $last))
    }
}

function Get-ListenerPort {
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory = $true)][System.Net.Sockets.TcpListener]$Listener)
    return ([System.Net.IPEndPoint]$Listener.LocalEndpoint).Port
}

function Get-ListenerAddress {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][System.Net.Sockets.TcpListener]$Listener)
    return ([System.Net.IPEndPoint]$Listener.LocalEndpoint).Address.ToString()
}

<# Example (in Start-ToolName.ps1):
. "$PSScriptRoot\LoopbackPort.ps1"
$listener = New-LoopbackListener -PreferredPort $Port
$actual = Get-ListenerPort -Listener $listener
if ($actual -ne $Port) { Write-Host "Port $Port is busy; using free loopback port $actual." -ForegroundColor Yellow }
$url = "http://127.0.0.1:$actual/"
if (-not $NoBrowser) { Start-Process $url }
try { while ($true) { $client = $listener.AcceptTcpClient(); $client.Close() } }
finally { $listener.Stop() }
#>
