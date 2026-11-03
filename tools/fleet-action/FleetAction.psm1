<#
.SYNOPSIS
    Fleet Action Framework v0.2.0 (Windows PowerShell 5.1). ASCII only. MIT.
.DESCRIPTION
    One registry of <app> <noun> <verb> actions shared by the GUI, the CLI, the loopback HTTP API
    and JSON job files. Spec: comms proposals/fleet-action-framework/README.md (refs comms #68).
    Every call returns one envelope: @{ ok; action; v; result | error; warnings }.
    Notes:
      - The session token is full authority over the app. confirm / --yes is an accident guard only.
      - Listeners must bind exactly http://127.0.0.1:<port>/ (use New-FleetHttpListener), never + or *.
#>
Set-StrictMode -Version 2
$script:FleetActionVersion = '0.2.0'
$script:Actions = @{}
$script:LogRoot = $env:LOCALAPPDATA
$script:MaxBodyBytes = 1048576
$script:ExitCodes = @{ OK = 0; E_INTERNAL = 1; E_ARGS = 2; E_NOTFOUND = 3; E_CONFIRM = 4; E_AUTH = 5; E_LENGTH = 2; E_TOOLARGE = 2 }
$script:HttpCodes = @{ OK = 200; E_INTERNAL = 500; E_ARGS = 400; E_NOTFOUND = 404; E_CONFIRM = 409; E_AUTH = 401; E_LENGTH = 411; E_TOOLARGE = 413 }
$script:InternalMessage = 'internal error (details in the local log)'

function Set-FleetActionLogRoot([string]$Root) { $script:LogRoot = $Root }

function Write-FleetActionLog([string]$App, [string]$Text) {
    try {
        if (-not $script:LogRoot -or -not $App) { return }
        $dir = Join-Path (Join-Path $script:LogRoot 'FleetHacker') $App
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $line = '{0} {1}{2}' -f ([DateTime]::UtcNow.ToString('o')), $Text, [Environment]::NewLine
        [IO.File]::AppendAllText((Join-Path $dir 'actions.log'), $line, (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

function Register-FleetAction {
    param([Parameter(Mandatory)][string]$App, [Parameter(Mandatory)][string]$Noun, [Parameter(Mandatory)][string]$Verb,
          [hashtable]$ArgsSchema = @{ type = 'object'; properties = @{} },
          [Parameter(Mandatory)][scriptblock]$Handler, [string]$Description = '', [switch]$Destructive)
    foreach ($w in @($App, $Noun, $Verb)) { if ($w -notmatch '^[a-z][a-z0-9-]*$') { throw "Bad action word '$w' (lowercase a-z0-9-)" } }
    $script:Actions["$App $Noun $Verb"] = [pscustomobject]@{ App = $App; Noun = $Noun; Verb = $Verb; Schema = $ArgsSchema
        Handler = $Handler; Description = $Description; Destructive = [bool]$Destructive }
}

function Clear-FleetAction { $script:Actions = @{} }

function New-FleetEnvelope {
    param([string]$Action, $Result = $null, [string]$Code = 'OK', [string]$Message = '', [string[]]$Warnings = @())
    $e = [ordered]@{ ok = ($Code -eq 'OK'); action = $Action; v = 1 }
    if ($Code -eq 'OK') { $e.result = $Result } else { $e.error = [ordered]@{ code = $Code; message = $Message } }
    $e.warnings = @($Warnings)
    [pscustomobject]$e
}

function Get-FleetExitCode([Parameter(Mandatory)]$Envelope) {
    if ($Envelope.ok) { return 0 }
    $c = $script:ExitCodes[$Envelope.error.code]; if ($null -eq $c) { 1 } else { $c }
}

function Get-FleetAction([string]$App) {
    # Discovery: what `<app> help --json` and GET /api/v1/actions return.
    @($script:Actions.Values | Where-Object { -not $App -or $_.App -eq $App } | Sort-Object App, Noun, Verb | ForEach-Object {
        [ordered]@{ name = "$($_.App) $($_.Noun) $($_.Verb)"; app = $_.App; noun = $_.Noun; verb = $_.Verb
                    description = $_.Description; destructive = $_.Destructive; args = $_.Schema } })
}

function ConvertTo-FleetHashtable($o) {
    if ($null -eq $o) { return @{} }
    if ($o -is [hashtable]) { return $o }
    if ($o -isnot [pscustomobject]) { throw 'arguments must be an object' }
    $h = @{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }; $h
}

function Test-FleetScalar($v) { $null -eq $v -or $v -is [string] -or $v -is [bool] -or $v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal] }

function Test-FleetArgs($Schema, [hashtable]$Arguments) {
    # Minimal JSON Schema subset: required, properties.type, enum, default. Undeclared args are always rejected.
    $props = @{}; if ($Schema.Contains('properties') -and $null -ne $Schema['properties']) { $props = ConvertTo-FleetHashtable $Schema['properties'] }
    foreach ($k in @($Arguments.Keys)) { if (-not $props.ContainsKey($k)) { return "unknown argument $k" } }
    if ($Schema.Contains('required')) { foreach ($r in @($Schema['required'])) { if ($r -and -not $Arguments.ContainsKey($r)) { return "$r is required" } } }
    foreach ($k in @($props.Keys)) {
        $p = ConvertTo-FleetHashtable $props[$k]
        if (-not $Arguments.ContainsKey($k)) { if ($p.ContainsKey('default')) { $Arguments[$k] = $p['default'] }; continue }
        $v = $Arguments[$k]; $t = [string]$p['type']
        if ($t -ne 'array' -and $t -ne 'object' -and -not (Test-FleetScalar $v)) { return "$k must be a single value" }
        switch ($t) {
            'boolean' { if ($v -is [string]) { if ($v -eq 'true' -or $v -eq 'false') { $Arguments[$k] = ($v -eq 'true') } else { return "$k must be true or false" } } elseif ($v -isnot [bool]) { return "$k must be a boolean" } }
            'integer' { $n = 0; if (-not [int]::TryParse([string]$v, [ref]$n)) { return "$k must be an integer" }; $Arguments[$k] = $n }
            'number'  { $d = 0.0; if (-not [double]::TryParse([string]$v, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return "$k must be a number" }; $Arguments[$k] = $d }
            'string'  { if ($v -isnot [string]) { return "$k must be a string" } }
        }
        if ($p.ContainsKey('enum') -and (@($p['enum']) -notcontains $Arguments[$k])) { return "$k must be one of: $(@($p['enum']) -join ', ')" }
    }
    $null
}

function Find-FleetAction([string]$App, [string]$Noun, [string]$Verb) {
    if ($App) { return $script:Actions["$App $Noun $Verb"] }
    $m = @($script:Actions.Values | Where-Object { $_.Noun -eq $Noun -and $_.Verb -eq $Verb })
    if ($m.Count -gt 1) { return 'AMBIGUOUS' }
    if ($m.Count -eq 1) { return $m[0] }
    $null
}

function Invoke-FleetAction {
    param([Parameter(Mandatory, Position = 0)][string]$Noun, [Parameter(Mandatory, Position = 1)][string]$Verb,
          [Parameter(Position = 2)]$Arguments = @{}, [string]$App, [switch]$Confirm, [switch]$DryRun)
    $name = (@($App, $Noun, $Verb) | Where-Object { $_ }) -join ' '
    try {
        $a = Find-FleetAction $App $Noun $Verb
        if ($a -eq 'AMBIGUOUS') { return New-FleetEnvelope $name -Code E_ARGS -Message "'$Noun $Verb' exists in more than one app; name the app" }
        if (-not $a) { return New-FleetEnvelope $name -Code E_NOTFOUND -Message "unknown action '$name'" }
        $name = "$($a.App) $Noun $Verb"
        try { $Arguments = (ConvertTo-FleetHashtable $Arguments).Clone() } catch { return New-FleetEnvelope $name -Code E_ARGS -Message 'arguments must be an object' }
        $bad = Test-FleetArgs $a.Schema $Arguments
        if ($bad) { return New-FleetEnvelope $name -Code E_ARGS -Message $bad }
        if ($DryRun) { return New-FleetEnvelope $name -Result ([ordered]@{ dryRun = $true; destructive = $a.Destructive; args = $Arguments }) }
        if ($a.Destructive -and -not $Confirm) { return New-FleetEnvelope $name -Code E_CONFIRM -Message 'destructive action: pass --yes (CLI) or "confirm": true (API / job step)' }
        if ($a.Destructive) { Write-FleetActionLog $a.App "destructive $name" }
        try { return New-FleetEnvelope $name -Result (& $a.Handler $Arguments) }
        catch { Write-FleetActionLog $a.App "error $name : $($_.Exception.Message)"; return New-FleetEnvelope $name -Code E_INTERNAL -Message $script:InternalMessage }
    } catch {
        Write-FleetActionLog $App "error $name : $($_.Exception.Message)"
        New-FleetEnvelope $name -Code E_INTERNAL -Message $script:InternalMessage
    }
}

function ConvertFrom-FleetArgs([string[]]$Argv) {
    # noun verb [--kebab-name value] [--flag] [--json] [--out f] [--yes] [--dry-run]
    $r = @{ Noun = $null; Verb = $null; Args = @{}; Json = $false; Out = $null; Yes = $false; DryRun = $false }
    $pos = @(); $i = 0
    while ($i -lt $Argv.Count) {
        $t = $Argv[$i]
        if ($t -like '--*') {
            $k = $t.Substring(2); $hasVal = ($i + 1 -lt $Argv.Count -and $Argv[$i + 1] -notlike '--*')
            switch ($k) {
                'json' { $r.Json = $true } 'yes' { $r.Yes = $true } 'dry-run' { $r.DryRun = $true }
                'out' { if (-not $hasVal) { throw '--out needs a file' }; $r.Out = $Argv[++$i] }
                default {
                    $ck = [regex]::Replace($k, '-([a-z0-9])', { param($m) $m.Groups[1].Value.ToUpper() })
                    if ($hasVal) { $r.Args[$ck] = $Argv[++$i] } else { $r.Args[$ck] = $true }
                }
            }
        } else { $pos += $t }
        $i++
    }
    if ($pos.Count -ge 1) { $r.Noun = $pos[0] }; if ($pos.Count -ge 2) { $r.Verb = $pos[1] }
    $r
}

function Write-FleetUtf8File([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path), $Text, (New-Object Text.UTF8Encoding($false)))
}

function Invoke-FleetCli {
    # Entry for <app>.ps1:  Invoke-FleetCli -App capstan -Argv $args; exit $LASTEXITCODE
    param([string[]]$Argv = @(), [string]$App)
    $p = $null
    try { $p = ConvertFrom-FleetArgs $Argv } catch { $env0 = New-FleetEnvelope 'cli' -Code E_ARGS -Message $_.Exception.Message }
    if ($p) {
        if (-not $p.Noun -or $p.Noun -eq 'help') { $env0 = New-FleetEnvelope 'help' -Result (Get-FleetAction $App); $p.Json = $true }
        elseif (-not $p.Verb) { $env0 = New-FleetEnvelope $p.Noun -Code E_ARGS -Message 'usage: <noun> <verb> [--arg value]' }
        else { $env0 = Invoke-FleetAction -App $App -Noun $p.Noun -Verb $p.Verb -Arguments $p.Args -Confirm:$p.Yes -DryRun:$p.DryRun }
    }
    $json = $env0 | ConvertTo-Json -Depth 20
    if ($p -and $p.Out) { Write-FleetUtf8File $p.Out $json }
    elseif (($p -and $p.Json) -or -not $p) { Write-Output $json }
    elseif ($env0.ok) { Write-Output "ok: $($env0.action)" }
    else { Write-Output "error $($env0.error.code): $($env0.error.message)" }
    $global:LASTEXITCODE = Get-FleetExitCode $env0
}

function Get-FleetProp($o, [string]$Name) {
    if ($o -is [hashtable]) { if ($o.ContainsKey($Name)) { return $o[$Name] } else { return $null } }
    if ($null -ne $o -and $o.PSObject.Properties[$Name]) { return $o.$Name }
    $null
}

function Invoke-FleetJob {
    # Job = { version: 1, steps: [ { id, app, noun, verb, args, confirm } ] }.
    # A destructive step runs only if that step has "confirm": true. Substitution: ${steps.<id>.result.<field>} only.
    # Substituted values come from earlier results: handlers must treat them as untrusted input.
    param([Parameter(Mandatory)]$Job, [switch]$DryRun, [switch]$ContinueOnError)
    try {
        if ($Job -is [string]) { $Job = Get-Content -LiteralPath $Job -Raw -Encoding UTF8 | ConvertFrom-Json }
        if ([string](Get-FleetProp $Job 'version') -ne '1') { return New-FleetEnvelope 'job run' -Code E_ARGS -Message 'unsupported job version' }
        $results = @{}; $out = @(); $failed = $null
        foreach ($s in @(Get-FleetProp $Job 'steps')) {
            $id = [string](Get-FleetProp $s 'id'); if (-not $id) { $id = "step$($out.Count + 1)" }
            $e = $null
            try {
                $args0 = @{}
                foreach ($kv in (ConvertTo-FleetHashtable (Get-FleetProp $s 'args')).GetEnumerator()) {
                    $v = $kv.Value
                    if ($v -is [string]) {
                        $v = [regex]::Replace($v, '\$\{steps\.([A-Za-z0-9_-]+)\.result\.([A-Za-z0-9_]+)\}', {
                            param($m)
                            if (-not $results.ContainsKey($m.Groups[1].Value)) { throw 'BADREF' }
                            [string](Get-FleetProp $results[$m.Groups[1].Value] $m.Groups[2].Value) })
                    }
                    $args0[$kv.Key] = $v
                }
                $e = Invoke-FleetAction -App ([string](Get-FleetProp $s 'app')) -Noun ([string](Get-FleetProp $s 'noun')) -Verb ([string](Get-FleetProp $s 'verb')) `
                        -Arguments $args0 -Confirm:([bool](Get-FleetProp $s 'confirm' | Where-Object { $_ -eq $true })) -DryRun:$DryRun
            } catch {
                $e = New-FleetEnvelope "step $id" -Code E_ARGS -Message 'bad step (check app/noun/verb/args and ${steps...} references)'
            }
            if ($e.ok) { $results[$id] = $e.result }
            $out += [pscustomobject]@{ id = $id; envelope = $e }
            if (-not $e.ok) { if (-not $failed) { $failed = $e.error }; if (-not $ContinueOnError) { break } }
        }
        if ($failed) { $r = New-FleetEnvelope 'job run' -Code $failed.code -Message "step failed: $($failed.message)"; $r | Add-Member steps $out; return $r }
        New-FleetEnvelope 'job run' -Result ([ordered]@{ steps = $out })
    } catch {
        Write-FleetActionLog '' "job error: $($_.Exception.Message)"
        New-FleetEnvelope 'job run' -Code E_INTERNAL -Message $script:InternalMessage
    }
}

function Test-FleetIsWindows { $env:OS -eq 'Windows_NT' }

function Get-FleetSessionTokenPath([string]$App, [string]$Root = $env:LOCALAPPDATA) {
    Join-Path (Join-Path (Join-Path $Root 'FleetHacker') $App) 'session.token'
}

function New-FleetSessionToken {
    # 32 random bytes, hex. The file is created empty, locked to the current user (inheritance off,
    # one FullControl rule for the current user) on Windows, or chmod 600 elsewhere, and only then written.
    # Call Remove-FleetSessionToken when the app stops.
    param([Parameter(Mandatory)][string]$App, [string]$Root = $env:LOCALAPPDATA)
    $path = Get-FleetSessionTokenPath $App $Root
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    [IO.File]::WriteAllBytes($path, (New-Object byte[] 0))
    if (Test-FleetIsWindows) {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = New-Object Security.AccessControl.FileSecurity
        $acl.SetOwner($me)
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
        [IO.File]::SetAccessControl($path, $acl)
    } else {
        & chmod 600 -- $path
        if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $path -Force; throw 'could not restrict session token file' }
    }
    $b = New-Object byte[] 32; $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($b); $rng.Dispose()
    $tok = -join ($b | ForEach-Object { $_.ToString('x2') })
    $fs = New-Object IO.FileStream($path, [IO.FileMode]::Truncate, [IO.FileAccess]::Write)
    try { $tb = [Text.Encoding]::ASCII.GetBytes($tok); $fs.Write($tb, 0, $tb.Length) } finally { $fs.Dispose() }
    $tok
}

function Remove-FleetSessionToken([Parameter(Mandatory)][string]$App, [string]$Root = $env:LOCALAPPDATA) {
    $path = Get-FleetSessionTokenPath $App $Root
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

function New-FleetHttpListener([Parameter(Mandatory)][int]$Port) {
    # The only supported prefix: exactly http://127.0.0.1:<port>/ (never +, * or a hostname).
    if ($Port -lt 1 -or $Port -gt 65535) { throw 'bad port' }
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://127.0.0.1:$Port/")
    $l
}

function Assert-FleetListenerPrefix([Parameter(Mandatory)][System.Net.HttpListener]$Listener) {
    foreach ($p in $Listener.Prefixes) { if ($p -notmatch '^http://127\.0\.0\.1:\d{1,5}/$') { throw "listener prefix '$p' is not allowed; bind exactly http://127.0.0.1:<port>/" } }
}

function Test-FleetHttpAuth([hashtable]$Headers, [int]$Port, [string]$Token) {
    # Returns $null when Host, Origin and Bearer token are all good, else an error code/message.
    $h = @{}; foreach ($k in $Headers.Keys) { $h[([string]$k).ToLower()] = [string]$Headers[$k] }
    if ($h['host'] -ne "127.0.0.1:$Port" -and $h['host'] -ne "localhost:$Port") { return 'bad Host' }
    if ($h.ContainsKey('origin') -and $h['origin'] -ne "http://127.0.0.1:$Port" -and $h['origin'] -ne "http://localhost:$Port") { return 'bad Origin' }
    $given = ''; if ($h['authorization'] -match '^Bearer\s+(\S+)$') { $given = $Matches[1] }
    if (-not $Token -or -not $given -or $given.Length -ne $Token.Length) { return 'missing or bad token' }
    $diff = 0; for ($i = 0; $i -lt $Token.Length; $i++) { $diff = $diff -bor ([int]$given[$i] -bxor [int]$Token[$i]) }
    if ($diff) { return 'missing or bad token' }
    $null
}

function Read-FleetBoundedBody([IO.Stream]$Stream, [long]$Length, [int]$Max = $script:MaxBodyBytes) {
    if ($Length -lt 0 -or $Length -gt $Max) { throw 'bad length' }
    $buf = New-Object byte[] $Length; $off = 0
    while ($off -lt $Length) { $n = $Stream.Read($buf, $off, [int]($Length - $off)); if ($n -le 0) { throw 'short body' }; $off += $n }
    (New-Object Text.UTF8Encoding($false, $true)).GetString($buf)
}

function Invoke-FleetHttpCore {
    # Order: auth (Host, Origin, token) -> length checks -> read body -> dispatch. Never throws.
    param([string]$Method, [string]$Path, [hashtable]$Headers, [long]$ContentLength = 0, [switch]$Chunked,
          [scriptblock]$ReadBody, [int]$Port, [string]$Token, [string]$App)
    $fail = { param($c, $m) @{ Status = $script:HttpCodes[$c]; Body = (New-FleetEnvelope 'http' -Code $c -Message $m) } }
    try {
        $bad = Test-FleetHttpAuth $Headers $Port $Token
        if ($bad) { return & $fail E_AUTH $bad }
        if ($Method -eq 'GET' -and $Path -eq '/api/v1/actions') { return @{ Status = 200; Body = (New-FleetEnvelope 'actions' -Result (Get-FleetAction $App)) } }
        if ($Method -ne 'POST') { return & $fail E_NOTFOUND 'use POST' }
        if ($Path -ne '/api/v1/job' -and $Path -notmatch '^/api/v1/([a-z][a-z0-9-]*)/([a-z][a-z0-9-]*)$') { return & $fail E_NOTFOUND 'no such route' }
        $noun = $null; $verb = $null; if ($Path -ne '/api/v1/job') { $noun = $Matches[1]; $verb = $Matches[2] }
        if ($Chunked -or $ContentLength -lt 0) { return & $fail E_LENGTH 'Content-Length required' }
        if ($ContentLength -gt $script:MaxBodyBytes) { return & $fail E_TOOLARGE 'body too large' }
        $in = @{}
        if ($ContentLength -gt 0) {
            try { $text = & $ReadBody } catch { return & $fail E_ARGS 'could not read body' }
            try { $in = ConvertTo-FleetHashtable ($text | ConvertFrom-Json) } catch { return & $fail E_ARGS 'body is not a JSON object' }
        }
        if ($null -eq $noun) { $e = Invoke-FleetJob -Job ([pscustomobject]$in) }
        else {
            $confirm = $false; if ($in.ContainsKey('confirm')) { $confirm = ($in['confirm'] -eq $true); $in.Remove('confirm') }
            $e = Invoke-FleetAction -App $App -Noun $noun -Verb $verb -Arguments $in -Confirm:$confirm
        }
        $c = 'OK'; if (-not $e.ok) { $c = $e.error.code }
        $s = $script:HttpCodes[$c]; if (-not $s) { $s = 500 }
        @{ Status = $s; Body = $e }
    } catch {
        Write-FleetActionLog $App "http error: $($_.Exception.Message)"
        & $fail E_INTERNAL $script:InternalMessage
    }
}

function Resolve-FleetHttpRequest {
    # Convenience wrapper for tests and in-process callers with the body already in hand.
    param([string]$Method, [string]$Path, [hashtable]$Headers, [string]$Body, [int]$Port, [string]$Token, [string]$App)
    $len = 0; if ($Body) { $len = (New-Object Text.UTF8Encoding($false)).GetByteCount($Body) }
    Invoke-FleetHttpCore -Method $Method -Path $Path -Headers $Headers -ContentLength $len -ReadBody { $Body }.GetNewClosure() -Port $Port -Token $Token -App $App
}

function Invoke-FleetHttpAction {
    # Plug into a listener from New-FleetHttpListener:
    #   if ($ctx.Request.Url.AbsolutePath -like '/api/v1/*') { Invoke-FleetHttpAction $ctx $port $tok -App capstan; continue }
    param([Parameter(Mandatory)][System.Net.HttpListenerContext]$Context, [int]$Port, [string]$Token, [string]$App)
    $res = $Context.Response
    try {
        $rq = $Context.Request
        $hd = @{}; foreach ($k in $rq.Headers.AllKeys) { $hd[$k] = $rq.Headers[$k] }
        $te = [string]$rq.Headers['Transfer-Encoding']
        $len = $rq.ContentLength64; if (-not $rq.HasEntityBody) { $len = 0 }
        $r = Invoke-FleetHttpCore -Method $rq.HttpMethod -Path $rq.Url.AbsolutePath -Headers $hd -ContentLength $len `
                -Chunked:($te -ne '') -ReadBody { Read-FleetBoundedBody $rq.InputStream $len } -Port $Port -Token $Token -App $App
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($r.Body | ConvertTo-Json -Depth 20))
        $res.StatusCode = $r.Status; $res.ContentType = 'application/json; charset=utf-8'
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
        Write-FleetActionLog $App "http error: $($_.Exception.Message)"
        try { $res.StatusCode = 500 } catch { }
    } finally {
        try { $res.Close() } catch { }
    }
}

Export-ModuleMember -Function Register-FleetAction, Clear-FleetAction, Get-FleetAction, Invoke-FleetAction, Invoke-FleetCli,
    Invoke-FleetJob, ConvertFrom-FleetArgs, New-FleetEnvelope, Get-FleetExitCode, New-FleetSessionToken, Remove-FleetSessionToken,
    Get-FleetSessionTokenPath, New-FleetHttpListener, Assert-FleetListenerPrefix, Test-FleetHttpAuth, Read-FleetBoundedBody,
    Invoke-FleetHttpCore, Resolve-FleetHttpRequest, Invoke-FleetHttpAction, Write-FleetUtf8File, Set-FleetActionLogRoot
