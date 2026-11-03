<#
.SYNOPSIS
    Fleet Action Framework v0.1.0 (Windows PowerShell 5.1). ASCII only. MIT.
.DESCRIPTION
    One registry of <app> <noun> <verb> actions shared by the GUI, the CLI, the loopback HTTP API
    and JSON job files. Spec: comms proposals/fleet-action-framework/README.md (refs comms #68).
    Every call returns one envelope: @{ ok; action; v; result | error; warnings }.
#>
Set-StrictMode -Version 2
$script:FleetActionVersion = '0.1.0'
$script:Actions = @{}
$script:ExitCodes = @{ OK = 0; E_INTERNAL = 1; E_ARGS = 2; E_NOTFOUND = 3; E_CONFIRM = 4; E_AUTH = 5 }
$script:HttpCodes = @{ OK = 200; E_INTERNAL = 500; E_ARGS = 400; E_NOTFOUND = 404; E_CONFIRM = 409; E_AUTH = 401 }

function Register-FleetAction {
    param([Parameter(Mandatory)][string]$App, [Parameter(Mandatory)][string]$Noun, [Parameter(Mandatory)][string]$Verb,
          [hashtable]$ArgsSchema = @{ type = 'object'; properties = @{} },
          [Parameter(Mandatory)][scriptblock]$Handler, [string]$Description = '', [switch]$Destructive)
    foreach ($w in @($Noun, $Verb)) { if ($w -notmatch '^[a-z][a-z0-9-]*$') { throw "Bad action word '$w' (lowercase a-z0-9-)" } }
    $script:Actions["$Noun $Verb"] = [pscustomobject]@{ App = $App; Noun = $Noun; Verb = $Verb; Schema = $ArgsSchema
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

function Get-FleetAction {
    # Discovery: what `<app> help --json` and GET /api/v1/actions return.
    @($script:Actions.Values | Sort-Object Noun, Verb | ForEach-Object {
        [ordered]@{ name = "$($_.App) $($_.Noun) $($_.Verb)"; noun = $_.Noun; verb = $_.Verb
                    description = $_.Description; destructive = $_.Destructive; args = $_.Schema } })
}

function ConvertTo-FleetHashtable($o) {
    if ($null -eq $o) { return @{} }
    if ($o -is [hashtable]) { return $o }
    $h = @{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }; $h
}

function Test-FleetArgs($Schema, [hashtable]$Arguments) {
    # Minimal JSON Schema subset: required, properties.type, enum, default. Returns error text or $null.
    $props = @{}; if ($Schema.Contains('properties')) { $props = ConvertTo-FleetHashtable $Schema.properties }
    if ($Schema.Contains('required')) { foreach ($r in @($Schema.required)) { if (-not $Arguments.ContainsKey($r)) { return "$r is required" } } }
    foreach ($k in @($props.Keys)) {
        $p = ConvertTo-FleetHashtable $props[$k]
        if (-not $Arguments.ContainsKey($k)) { if ($p.ContainsKey('default')) { $Arguments[$k] = $p['default'] }; continue }
        $v = $Arguments[$k]
        switch ([string]$p['type']) {
            'boolean' { if ($v -is [string]) { if ($v -in 'true', 'false') { $Arguments[$k] = ($v -eq 'true') } else { return "$k must be true or false" } } elseif ($v -isnot [bool]) { return "$k must be a boolean" } }
            'integer' { $n = 0; if (-not [int]::TryParse([string]$v, [ref]$n)) { return "$k must be an integer" }; $Arguments[$k] = $n }
            'number'  { $d = 0.0; if (-not [double]::TryParse([string]$v, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return "$k must be a number" }; $Arguments[$k] = $d }
            'string'  { if ($v -isnot [string]) { return "$k must be a string" } }
        }
        if ($p.ContainsKey('enum') -and (@($p['enum']) -notcontains $Arguments[$k])) { return "$k must be one of: $(@($p['enum']) -join ', ')" }
    }
    foreach ($k in @($Arguments.Keys)) { if ($props.Count -and -not $props.ContainsKey($k)) { return "unknown argument $k" } }
    $null
}

function Invoke-FleetAction {
    param([Parameter(Mandatory)][string]$Noun, [Parameter(Mandatory)][string]$Verb, $Arguments = @{}, [switch]$Confirm, [switch]$DryRun)
    $Arguments = (ConvertTo-FleetHashtable $Arguments).Clone()
    $a = $script:Actions["$Noun $Verb"]
    if (-not $a) { return New-FleetEnvelope "$Noun $Verb" -Code E_NOTFOUND -Message "unknown action '$Noun $Verb'" }
    $name = "$($a.App) $Noun $Verb"
    $bad = Test-FleetArgs $a.Schema $Arguments
    if ($bad) { return New-FleetEnvelope $name -Code E_ARGS -Message $bad }
    if ($DryRun) { return New-FleetEnvelope $name -Result ([ordered]@{ dryRun = $true; args = $Arguments }) }
    if ($a.Destructive -and -not $Confirm) { return New-FleetEnvelope $name -Code E_CONFIRM -Message 'destructive action: pass --yes (CLI) or "confirm": true (API)' }
    try { New-FleetEnvelope $name -Result (& $a.Handler $Arguments) }
    catch { New-FleetEnvelope $name -Code E_INTERNAL -Message $_.Exception.Message }
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
    # Entry for <app>.ps1:  exit (Invoke-FleetCli -Argv $args)
    param([string[]]$Argv = @())
    $p = $null
    try { $p = ConvertFrom-FleetArgs $Argv } catch { $env0 = New-FleetEnvelope 'cli' -Code E_ARGS -Message $_.Exception.Message }
    if ($p) {
        if (-not $p.Noun -or $p.Noun -eq 'help') { $env0 = New-FleetEnvelope 'help' -Result (Get-FleetAction); $p.Json = $true }
        elseif (-not $p.Verb) { $env0 = New-FleetEnvelope $p.Noun -Code E_ARGS -Message 'usage: <noun> <verb> [--arg value]' }
        else { $env0 = Invoke-FleetAction -Noun $p.Noun -Verb $p.Verb -Arguments $p.Args -Confirm:$p.Yes -DryRun:$p.DryRun }
    }
    $json = $env0 | ConvertTo-Json -Depth 20
    if ($p -and $p.Out) { Write-FleetUtf8File $p.Out $json }
    elseif (($p -and $p.Json) -or -not $p) { Write-Output $json }
    elseif ($env0.ok) { Write-Output "ok: $($env0.action)" }
    else { Write-Output "error $($env0.error.code): $($env0.error.message)" }
    Get-FleetExitCode $env0 | Out-Null
    $global:LASTEXITCODE = Get-FleetExitCode $env0
}

function Invoke-FleetJob {
    # Job = @{ version = 1; steps = @( @{ id; app; noun; verb; args } ) }. ${steps.<id>.result.<field>} substitution only.
    param([Parameter(Mandatory)]$Job, [switch]$Confirm, [switch]$DryRun, [switch]$ContinueOnError)
    if ($Job -is [string]) { $Job = Get-Content -LiteralPath $Job -Raw -Encoding UTF8 | ConvertFrom-Json }
    if ([int]$Job.version -ne 1) { return New-FleetEnvelope 'job run' -Code E_ARGS -Message "unsupported job version '$($Job.version)'" }
    $results = [ordered]@{}; $out = @(); $failed = $false
    foreach ($s in @($Job.steps)) {
        $args0 = @{}
        $sa = $null; if ($s.PSObject.Properties['args']) { $sa = $s.args }
        foreach ($kv in (ConvertTo-FleetHashtable $sa).GetEnumerator()) {
            $v = $kv.Value
            if ($v -is [string]) {
                $v = [regex]::Replace($v, '\$\{steps\.([A-Za-z0-9_-]+)\.result\.([A-Za-z0-9_]+)\}', {
                    param($m) $r = $results[$m.Groups[1].Value]
                    if ($null -eq $r) { throw "step '$($m.Groups[1].Value)' has no result" }
                    [string](ConvertTo-FleetHashtable $r)[$m.Groups[2].Value] })
            }
            $args0[$kv.Key] = $v
        }
        $e = Invoke-FleetAction -Noun $s.noun -Verb $s.verb -Arguments $args0 -Confirm:$Confirm -DryRun:$DryRun
        $id = if ($s.PSObject.Properties['id'] -and $s.id) { [string]$s.id } else { "step$($out.Count + 1)" }
        if ($e.ok) { $results[$id] = $e.result }
        $out += [pscustomobject]@{ id = $id; envelope = $e }
        if (-not $e.ok) { $failed = $true; if (-not $ContinueOnError) { break } }
    }
    if ($failed) { $first = @($out | Where-Object { -not $_.envelope.ok })[0].envelope.error
        $r = New-FleetEnvelope 'job run' -Code $first.code -Message "step failed: $($first.message)"; $r | Add-Member steps $out; return $r }
    New-FleetEnvelope 'job run' -Result ([ordered]@{ steps = $out })
}

function New-FleetSessionToken {
    # 32 random bytes, hex, written to %LOCALAPPDATA%\FleetHacker\<app>\session.token (user profile ACL).
    param([Parameter(Mandatory)][string]$App, [string]$Root = $env:LOCALAPPDATA)
    $b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    $tok = -join ($b | ForEach-Object { $_.ToString('x2') })
    $dir = Join-Path (Join-Path $Root 'FleetHacker') $App
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-FleetUtf8File (Join-Path $dir 'session.token') $tok
    $tok
}

function Resolve-FleetHttpRequest {
    # Pure request handler (testable). Returns @{ Status; Body(envelope) }.
    param([string]$Method, [string]$Path, [hashtable]$Headers, [string]$Body, [int]$Port, [string]$Token)
    $h = @{}; foreach ($k in $Headers.Keys) { $h[$k.ToLower()] = [string]$Headers[$k] }
    $fail = { param($c, $m) @{ Status = $script:HttpCodes[$c]; Body = (New-FleetEnvelope 'http' -Code $c -Message $m) } }
    if ($h['host'] -notin "127.0.0.1:$Port", "localhost:$Port") { return & $fail E_AUTH 'bad Host' }
    if ($h.ContainsKey('origin') -and $h['origin'] -notin "http://127.0.0.1:$Port", "http://localhost:$Port") { return & $fail E_AUTH 'bad Origin' }
    $given = ($h['authorization'] -replace '^Bearer\s+', '')
    if (-not $Token -or -not $given -or $given.Length -ne $Token.Length) { return & $fail E_AUTH 'missing or bad token' }
    $diff = 0; for ($i = 0; $i -lt $Token.Length; $i++) { $diff = $diff -bor ([int]$given[$i] -bxor [int]$Token[$i]) }
    if ($diff) { return & $fail E_AUTH 'missing or bad token' }
    if ($Method -eq 'GET' -and $Path -eq '/api/v1/actions') { return @{ Status = 200; Body = (New-FleetEnvelope 'actions' -Result (Get-FleetAction)) } }
    if ($Method -ne 'POST') { return & $fail E_NOTFOUND 'use POST' }
    try { $in = if ($Body) { ConvertTo-FleetHashtable ($Body | ConvertFrom-Json) } else { @{} } } catch { return & $fail E_ARGS 'body is not JSON' }
    $confirm = $false; if ($in.ContainsKey('confirm')) { $confirm = [bool]$in['confirm']; $in.Remove('confirm') }
    if ($Path -eq '/api/v1/job') { $e = Invoke-FleetJob -Job ([pscustomobject]$in) -Confirm:$confirm }
    elseif ($Path -match '^/api/v1/([a-z][a-z0-9-]*)/([a-z][a-z0-9-]*)$') { $e = Invoke-FleetAction -Noun $Matches[1] -Verb $Matches[2] -Arguments $in -Confirm:$confirm }
    else { return & $fail E_NOTFOUND 'no such route' }
    $c = if ($e.ok) { 'OK' } else { $e.error.code }
    @{ Status = $script:HttpCodes[$c]; Body = $e }
}

function Invoke-FleetHttpAction {
    # Plug into an existing HttpListener loop: if ($ctx.Request.Url.AbsolutePath -like '/api/v1/*') { Invoke-FleetHttpAction $ctx $port $tok; continue }
    param([Parameter(Mandatory)][System.Net.HttpListenerContext]$Context, [int]$Port, [string]$Token)
    $rq = $Context.Request; $hd = @{}; foreach ($k in $rq.Headers.AllKeys) { $hd[$k] = $rq.Headers[$k] }
    $body = ''; if ($rq.HasEntityBody) { $sr = New-Object IO.StreamReader($rq.InputStream, [Text.Encoding]::UTF8); $body = $sr.ReadToEnd(); $sr.Close() }
    $r = Resolve-FleetHttpRequest -Method $rq.HttpMethod -Path $rq.Url.AbsolutePath -Headers $hd -Body $body -Port $Port -Token $Token
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($r.Body | ConvertTo-Json -Depth 20))
    $Context.Response.StatusCode = $r.Status; $Context.Response.ContentType = 'application/json; charset=utf-8'
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length); $Context.Response.Close()
}

Export-ModuleMember -Function Register-FleetAction, Clear-FleetAction, Get-FleetAction, Invoke-FleetAction, Invoke-FleetCli,
    Invoke-FleetJob, ConvertFrom-FleetArgs, New-FleetEnvelope, Get-FleetExitCode, New-FleetSessionToken,
    Resolve-FleetHttpRequest, Invoke-FleetHttpAction, Write-FleetUtf8File
