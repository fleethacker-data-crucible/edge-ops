<#
.SYNOPSIS
  Shared speech-in client for Fleet apps. Windows PowerShell 5.1. ASCII only.
.DESCRIPTION
  Sends one audio file to Fairlead at http://127.0.0.1:8776/v1/audio/transcriptions.
  The URL must be http on 127.0.0.1 or localhost, with that exact path. Redirects are not followed.
  The client key is a parameter. It is not written, logged, or copied into an error message.
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
        $req = [System.Net.HttpWebRequest]::Create($Endpoint)
        $req.Method = 'POST'
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

Export-ModuleMember -Function Test-SpeechInEndpoint, Get-SpeechInFallback, Invoke-SpeechIn
