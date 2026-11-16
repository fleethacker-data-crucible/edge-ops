<#
.SYNOPSIS
  Shared speech-in client for Fleet apps. Windows PowerShell 5.1. ASCII only.
.DESCRIPTION
  Sends one audio file to Fairlead at http://127.0.0.1:8776/v1/audio/transcriptions.
  The URL must be http on 127.0.0.1 or localhost, with that exact path. Redirects are not followed.
  The client key is a parameter. It is not written, logged, or copied into an error message.
  Before the key is sent, GET /__fleethacker/id must report tool fairlead, exactly one loopback
  listener whose pid matches, and a path that matches that process. The id probe and the request
  that carries the key both set Proxy to null.
  This module does not carry Whisper weights. PacketRat's release carries those assets.
  Windows speech recognition is the fallback when this call cannot run; Get-SpeechInFallback only
  reports whether the System.Speech assembly loads. It does not start a recognizer.
#>
$ErrorActionPreference = 'Stop'

$script:DefaultEndpoint = 'http://127.0.0.1:8776/v1/audio/transcriptions'
$script:MaxAudioBytes = 26214400
$script:MaxResponseBytes = 1048576

function New-SpeechInResult {
    param([bool]$Ok, [string]$Code, [string]$Message, [string]$Text = '')
    [pscustomobject]@{ Ok = $Ok; Code = $Code; Message = $Message; Text = $Text }
}

function Test-SpeechInEndpoint {
    <#
    .SYNOPSIS
      True only for http://127.0.0.1:<port>/v1/audio/transcriptions or the localhost form of that URL.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Endpoint)
    try { $u = [Uri]$Endpoint } catch { return $false }
    if ($u.Scheme -ne 'http') { return $false }
    if ($u.UserInfo) { return $false }
    $hostName = $u.Host
    if ($hostName -ne '127.0.0.1' -and $hostName -ne 'localhost') { return $false }
    if ($u.AbsolutePath -ne '/v1/audio/transcriptions') { return $false }
    if ($u.Query -or $u.Fragment) { return $false }
    if ($u.Port -lt 1 -or $u.Port -gt 65535) { return $false }
    return $true
}

function Test-SpeechInIsWindows {
    # Win32NT on Windows PowerShell 5.1 and on pwsh. Never decided by whether a path exists.
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Test-SpeechInIsLinux {
    # $IsLinux exists on PowerShell 6+. On Windows PowerShell 5.1 it is undefined, which is false.
    $var = Get-Variable -Name IsLinux -ErrorAction SilentlyContinue
    if ($null -eq $var) { return $false }
    return [bool]$var.Value
}

function Get-SpeechInLinuxListeners {
    param([Parameter(Mandatory = $true)][int]$Port, [Parameter(Mandatory = $true)][string]$ProcRoot)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($table in @('tcp', 'tcp6')) {
        $file = Join-Path (Join-Path $ProcRoot 'net') $table
        if (-not (Test-Path -LiteralPath $file)) { continue }
        foreach ($line in @(Get-Content -LiteralPath $file)) {
            $parts = @($line -split '\s+' | Where-Object { $_ })
            if ($parts.Count -lt 10) { continue }
            if ($parts[3] -ne '0A') { continue }
            $addr = [string]$parts[1]
            $colon = $addr.LastIndexOf(':')
            if ($colon -lt 1) { continue }
            $hexPort = $addr.Substring($colon + 1)
            $listenPort = 0
            if (-not [int]::TryParse($hexPort, [System.Globalization.NumberStyles]::HexNumber, [cultureinfo]::InvariantCulture, [ref]$listenPort)) { continue }
            if ($listenPort -ne $Port) { continue }
            $hexIp = $addr.Substring(0, $colon)
            $ip = $hexIp
            $loop = $false
            if ($hexIp.Length -eq 8) {
                $n = [Convert]::ToUInt32($hexIp, 16)
                $ip = '{0}.{1}.{2}.{3}' -f ($n -band 0xFF), (($n -shr 8) -band 0xFF), (($n -shr 16) -band 0xFF), (($n -shr 24) -band 0xFF)
                $loop = ($ip -eq '127.0.0.1')
            }
            elseif ($hexIp -eq '00000000000000000000000001000000') { $ip = '::1'; $loop = $true }
            $inode = [string]$parts[9]
            $owner = 0
            $needle = 'socket:[' + $inode + ']'
            foreach ($dir in @([System.IO.Directory]::GetDirectories($ProcRoot))) {
                $procName = [System.IO.Path]::GetFileName($dir)
                if ($procName -notmatch '^\d+$') { continue }
                $fdDir = Join-Path $dir 'fd'
                if (-not [System.IO.Directory]::Exists($fdDir)) { continue }
                $fds = $null
                try { $fds = [System.IO.Directory]::GetFiles($fdDir) } catch { continue }
                foreach ($fd in $fds) {
                    $target = ''
                    try {
                        $item = Get-Item -LiteralPath $fd -Force -ErrorAction Stop
                        if ($item.Target) { $target = [string]@($item.Target)[0] }
                    } catch { continue }
                    if ($target -eq $needle) { $owner = [int]$procName; break }
                }
                if ($owner -ne 0) { break }
            }
            $rows.Add([pscustomobject]@{ Address = $ip; Pid = $owner; Loopback = [bool]$loop })
        }
    }
    $out = @()
    foreach ($r in $rows) { $out += $r }
    return $out
}

function Get-SpeechInWindowsListeners {
    param([Parameter(Mandatory = $true)][int]$Port)
    $rows = New-Object System.Collections.Generic.List[object]
    $sys = [Environment]::SystemDirectory
    if (-not $sys) { return @() }
    $netstat = Join-Path $sys 'netstat.exe'
    if (-not (Test-Path -LiteralPath $netstat)) { return @() }
    $lines = @(& $netstat -ano -p TCP 2>$null) + @(& $netstat -ano -p TCPv6 2>$null)
    foreach ($line in $lines) {
        if ($line -match '^\s*TCP\s+(\S+):(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$' -and [int]$Matches[2] -eq $Port) {
            $addr = [string]$Matches[1]
            $loop = ($addr -eq '127.0.0.1' -or $addr -eq '[::1]' -or $addr -eq '::1')
            $rows.Add([pscustomobject]@{ Address = $addr; Pid = [int]$Matches[3]; Loopback = [bool]$loop })
        }
    }
    $out = @()
    foreach ($r in $rows) { $out += $r }
    return $out
}

function Get-SpeechInLoopbackListeners {
    # Listeners on this port. Loopback is 127.0.0.1 or ::1. The OS picks the source, never a path that a user can create.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$Port)
    if (Test-SpeechInIsWindows) { return @(Get-SpeechInWindowsListeners -Port $Port) }
    if (Test-SpeechInIsLinux) { return @(Get-SpeechInLinuxListeners -Port $Port -ProcRoot '/proc') }
    return @()
}

function Test-SpeechInProcessPath {
    param([string]$Reported, [int]$ProcessId)
    if ([string]::IsNullOrWhiteSpace($Reported) -or $ProcessId -le 0) { return $false }
    $want = $Reported.Trim().Trim('"')
    $exe = ''
    $argv = @()
    if (Test-SpeechInIsWindows) {
        if ($want -notmatch '^(?:[A-Za-z]:\\|\\\\)') { return $false }
        $proc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
        if (-not $proc) { return $false }
        $exe = [string]$proc.ExecutablePath
        $cmd = [string]$proc.CommandLine
        if ($cmd -match '(?i)(?:^|\s)-(?:File|f)\s+"([^"]+)"' -or $cmd -match '(?i)(?:^|\s)-(?:File|f)\s+(\S+)') {
            $argv = @('-File', [string]$Matches[1])
        }
    }
    elseif (Test-SpeechInIsLinux) {
        if (-not $want.StartsWith('/')) { return $false }
        $exeLink = Join-Path '/proc' ($ProcessId.ToString() + '/exe')
        if (-not (Test-Path -LiteralPath $exeLink)) { return $false }
        try {
            $item = Get-Item -LiteralPath $exeLink -Force -ErrorAction Stop
            if ($item.Target) { $exe = [string]@($item.Target)[0] }
        } catch { return $false }
        $cmdLine = Join-Path '/proc' ($ProcessId.ToString() + '/cmdline')
        if (Test-Path -LiteralPath $cmdLine) {
            $raw = [System.IO.File]::ReadAllBytes($cmdLine)
            $argv = @([System.Text.Encoding]::UTF8.GetString($raw).Split([char]0) | Where-Object { $_ })
        }
    }
    else { return $false }
    if ($exe -and [string]::Equals($exe.TrimEnd('\', '/'), $want.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { return $true }
    for ($i = 0; $i -lt $argv.Count - 1; $i++) {
        $a = [string]$argv[$i]
        if ($a -eq '-File' -or $a -eq '-f' -or $a -eq '/File') {
            $script = [string]$argv[$i + 1]
            if ([string]::Equals($script.TrimEnd('\', '/'), $want.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    }
    return $false
}

function Test-SpeechInFairleadDecision {
    <#
    .SYNOPSIS
      ok, or the reason the endpoint is refused: tool, listeners, pid, path.
    #>
    [CmdletBinding()]
    param(
        [string]$Tool,
        [int]$ReportedPid,
        [string]$ReportedPath,
        [Parameter(Mandatory = $true)]$Listeners
    )
    if ($Tool -ne 'fairlead') { return 'tool' }
    $all = @($Listeners)
    $foreign = @($all | Where-Object { -not $_.Loopback })
    if ($foreign.Count -gt 0) { return 'listeners' }
    $loop = @($all | Where-Object { $_.Loopback })
    if ($loop.Count -ne 1) { return 'listeners' }
    if ([int]$loop[0].Pid -ne $ReportedPid -or $ReportedPid -le 0) { return 'pid' }
    if ([string]::IsNullOrWhiteSpace($ReportedPath)) { return 'path' }
    if (-not (Test-SpeechInProcessPath -Reported $ReportedPath -ProcessId $ReportedPid)) { return 'path' }
    return 'ok'
}

function Read-SpeechInFairleadId {
    param([Parameter(Mandatory = $true)][string]$Origin)
    $req = [System.Net.HttpWebRequest]::Create($Origin + '/__fleethacker/id')
    $req.Method = 'GET'
    $req.Proxy = $null
    $req.AllowAutoRedirect = $false
    $req.Timeout = 5000
    $req.ReadWriteTimeout = 5000
    $req.Accept = 'application/json'
    $resp = $null
    try {
        try { $resp = $req.GetResponse() }
        catch [System.Net.WebException] {
            if ($_.Exception.Response) { $resp = $_.Exception.Response } else { return $null }
        }
        if ([int]$resp.StatusCode -ne 200) { return $null }
        $read = $resp.GetResponseStream()
        $buf = New-Object byte[] 8192
        $got = 0
        try {
            while ($got -lt $buf.Length) {
                $n = $read.Read($buf, $got, $buf.Length - $got)
                if ($n -le 0) { break }
                $got += $n
            }
        }
        finally { $read.Dispose() }
        if ($got -ge $buf.Length) { return $null }
        $text = (New-Object System.Text.UTF8Encoding($false)).GetString($buf, 0, $got)
        $id = $text | ConvertFrom-Json
        $tool = ''
        $prop = $id.PSObject.Properties['tool']
        if ($prop) { $tool = [string]$prop.Value }
        $procId = 0
        $prop = $id.PSObject.Properties['pid']
        if ($prop) { $procId = [int]$prop.Value }
        $path = ''
        $prop = $id.PSObject.Properties['path']
        if ($prop) { $path = [string]$prop.Value }
        return [pscustomobject]@{ Tool = $tool; Pid = $procId; Path = $path }
    }
    catch { return $null }
    finally { if ($resp) { try { $resp.Close() } catch { } } }
}

function Get-SpeechInFallback {
    <#
    .SYNOPSIS
      Returns windows when System.Speech loads, otherwise none. Does not start a recognizer.
    #>
    [CmdletBinding()]
    param()
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        return 'windows'
    }
    catch { return 'none' }
}

function Invoke-SpeechIn {
    <#
    .SYNOPSIS
      Posts one audio file to the loopback transcription route and returns ok, code, message, and text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AudioPath,
        [string]$Endpoint = $script:DefaultEndpoint,
        [Parameter(Mandatory = $true)][string]$ClientKey,
        [int]$TimeoutSec = 60
    )
    if (-not (Test-SpeechInEndpoint -Endpoint $Endpoint)) {
        return (New-SpeechInResult $false 'E_FORBIDDEN' 'Speech endpoint must be http://127.0.0.1 or localhost, path /v1/audio/transcriptions.')
    }
    if (-not $ClientKey -or $ClientKey.Length -gt 256 -or $ClientKey -match '[\r\n]') {
        return (New-SpeechInResult $false 'E_ARGS' 'Client key is missing or not usable.')
    }
    if ($TimeoutSec -lt 1 -or $TimeoutSec -gt 180) {
        return (New-SpeechInResult $false 'E_ARGS' 'Timeout must be from 1 to 180 seconds.')
    }
    if (-not (Test-Path -LiteralPath $AudioPath -PathType Leaf)) {
        return (New-SpeechInResult $false 'E_ARGS' 'Audio file was not found.')
    }
    $audioItem = Get-Item -LiteralPath $AudioPath -Force
    if (($audioItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return (New-SpeechInResult $false 'E_ARGS' 'Audio path is a link.')
    }
    $link = $audioItem.PSObject.Properties['LinkType']
    if ($null -ne $link -and $link.Value) {
        return (New-SpeechInResult $false 'E_ARGS' 'Audio path is a link.')
    }
    if ($audioItem.Length -lt 1 -or $audioItem.Length -gt $script:MaxAudioBytes) {
        return (New-SpeechInResult $false 'E_TOOLARGE' 'Audio file is empty or over 25 MB.')
    }
    $safeName = [System.IO.Path]::GetFileName($audioItem.Name)
    if ($safeName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$') { $safeName = 'audio.bin' }

    $endpointUri = [Uri]$Endpoint
    $origin = 'http://127.0.0.1:' + $endpointUri.Port
    $pinned = $origin + '/v1/audio/transcriptions'
    $id = $null
    try { $id = Read-SpeechInFairleadId -Origin $origin } catch { $id = $null }
    if (-not $id) { return (New-SpeechInResult $false 'E_FORBIDDEN' 'Speech endpoint did not identify itself.') }
    $listeners = @(Get-SpeechInLoopbackListeners -Port $endpointUri.Port)
    $decision = Test-SpeechInFairleadDecision -Tool $id.Tool -ReportedPid $id.Pid -ReportedPath $id.Path -Listeners $listeners
    if ($decision -eq 'tool') { return (New-SpeechInResult $false 'E_FORBIDDEN' 'Speech endpoint is not Fairlead.') }
    if ($decision -eq 'listeners') { return (New-SpeechInResult $false 'E_FORBIDDEN' 'Speech endpoint is not exactly one loopback listener.') }
    if ($decision -eq 'pid') { return (New-SpeechInResult $false 'E_FORBIDDEN' 'Speech endpoint pid does not hold the port.') }
    if ($decision -ne 'ok') { return (New-SpeechInResult $false 'E_FORBIDDEN' 'Speech endpoint path does not match the process.') }

    $boundary = 'FleetSpeech' + [guid]::NewGuid().ToString('N')
    $enc = New-Object System.Text.UTF8Encoding($false)
    $pre = $enc.GetBytes(('--' + $boundary + "`r`n" +
        "Content-Disposition: form-data; name=`"model`"`r`n`r`n" +
        "whisper-1`r`n" +
        '--' + $boundary + "`r`n" +
        "Content-Disposition: form-data; name=`"file`"; filename=`"$safeName`"`r`n" +
        "Content-Type: application/octet-stream`r`n`r`n"))
    $post = $enc.GetBytes("`r`n--" + $boundary + "--`r`n")
    $bodyStream = $null
    $req = $null
    $resp = $null
    try {
        $bodyStream = New-Object System.IO.MemoryStream
        $bodyStream.Write($pre, 0, $pre.Length)
        $inFile = [System.IO.File]::OpenRead($audioItem.FullName)
        try { $inFile.CopyTo($bodyStream) } finally { $inFile.Dispose() }
        $bodyStream.Write($post, 0, $post.Length)
        $req = [System.Net.HttpWebRequest]::Create($pinned)
        $req.Method = 'POST'
        $req.Proxy = $null
        $req.AllowAutoRedirect = $false
        $req.Timeout = $TimeoutSec * 1000
        $req.ReadWriteTimeout = $TimeoutSec * 1000
        $req.ContentType = 'multipart/form-data; boundary=' + $boundary
        $req.Accept = 'application/json'
        $req.Headers['Authorization'] = 'Bearer ' + $ClientKey
        $req.ContentLength = $bodyStream.Length
        $bodyStream.Position = 0
        $out = $req.GetRequestStream()
        try { $bodyStream.CopyTo($out) } finally { $out.Dispose() }
        try { $resp = $req.GetResponse() }
        catch [System.Net.WebException] {
            $web = $_.Exception
            if ($web.Response) { $resp = $web.Response } else { return (New-SpeechInResult $false 'E_INTERNAL' 'Speech endpoint did not answer.') }
        }
        $status = [int]$resp.StatusCode
        if ($status -ge 300 -and $status -lt 400) {
            return (New-SpeechInResult $false 'E_FORBIDDEN' 'Speech endpoint refused a redirect.')
        }
        if ($status -eq 401 -or $status -eq 403) {
            return (New-SpeechInResult $false 'E_AUTH' 'Speech endpoint rejected the client key.')
        }
        $read = $resp.GetResponseStream()
        $buf = New-Object byte[] ($script:MaxResponseBytes + 1)
        $got = 0
        try {
            while ($got -le $script:MaxResponseBytes) {
                $n = $read.Read($buf, $got, $buf.Length - $got)
                if ($n -le 0) { break }
                $got += $n
            }
        }
        finally { $read.Dispose() }
        if ($got -gt $script:MaxResponseBytes) {
            return (New-SpeechInResult $false 'E_TOOLARGE' 'Speech response is over 1 MB.')
        }
        if ($status -ne 200) {
            return (New-SpeechInResult $false 'E_INTERNAL' 'Speech endpoint returned an error.')
        }
        $textBody = $enc.GetString($buf, 0, $got)
        try { $parsed = $textBody | ConvertFrom-Json } catch { return (New-SpeechInResult $false 'E_ARGS' 'Speech response was not JSON.') }
        $prop = $parsed.PSObject.Properties['text']
        if ($null -eq $prop -or $prop.Value -isnot [string]) {
            return (New-SpeechInResult $false 'E_ARGS' 'Speech response has no text.')
        }
        return (New-SpeechInResult $true 'OK' '' ([string]$prop.Value))
    }
    catch {
        return (New-SpeechInResult $false 'E_INTERNAL' 'Speech request failed.')
    }
    finally {
        if ($resp) { try { $resp.Close() } catch { } }
        if ($bodyStream) { $bodyStream.Dispose() }
    }
}

Export-ModuleMember -Function Test-SpeechInEndpoint, Test-SpeechInFairleadDecision, Get-SpeechInFallback, Invoke-SpeechIn
