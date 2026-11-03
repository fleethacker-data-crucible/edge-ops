# Pester 5. Runs on Windows PowerShell 5.1 and pwsh.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FleetAction.psm1') -Force
    Set-FleetActionLogRoot ''
    $script:Tok = 'a' * 64
    $script:Hd = @{ Host = '127.0.0.1:8900'; Authorization = "Bearer $('a' * 64)" }
}
Describe 'FleetAction' {
BeforeEach {
    Clear-FleetAction
    Register-FleetAction -App demo -Noun marker -Verb add -Description 'Add a marker' -ArgsSchema @{
        type = 'object'; required = @('clip'); properties = @{ clip = @{ type = 'string' }; at = @{ type = 'integer'; default = 0 }; loud = @{ type = 'boolean' } } } `
        -Handler { param($a) @{ markerId = "m_$($a.clip)_$($a.at)" } }
    Register-FleetAction -App demo -Noun marker -Verb remove -Destructive -ArgsSchema @{ type = 'object'; properties = @{ id = @{ type = 'string' } } } -Handler { param($a) @{ removed = $a.id } }
    Register-FleetAction -App demo -Noun boom -Verb go -Handler { throw 'kaboom secret path C:\x' }
}
Describe 'Invoke-FleetAction' {
    It 'runs and returns an ok envelope' { $e = Invoke-FleetAction marker add @{ clip = 'c1'; at = '5' }; $e.ok | Should -BeTrue; $e.result.markerId | Should -Be 'm_c1_5'; $e.action | Should -Be 'demo marker add' }
    It 'applies defaults' { (Invoke-FleetAction marker add @{ clip = 'c1' }).result.markerId | Should -Be 'm_c1_0' }
    It 'rejects missing required' { $e = Invoke-FleetAction marker add @{}; $e.error.code | Should -Be 'E_ARGS'; Get-FleetExitCode $e | Should -Be 2 }
    It 'rejects bad types and unknown args' {
        (Invoke-FleetAction marker add @{ clip = 'c'; at = 'x' }).error.code | Should -Be 'E_ARGS'
        (Invoke-FleetAction marker add @{ clip = 'c'; nope = 1 }).error.message | Should -Match 'unknown'
    }
    It 'rejects any arg when the schema declares none' { (Invoke-FleetAction boom go @{ x = 1 }).error.message | Should -Be 'unknown argument x' }
    It 'rejects non-scalar values for scalar args' { (Invoke-FleetAction marker add @{ clip = @('a', 'b') }).error.message | Should -Match 'single value' }
    It 'unknown action is E_NOTFOUND' { Get-FleetExitCode (Invoke-FleetAction foo bar) | Should -Be 3 }
    It 'destructive needs confirm' { (Invoke-FleetAction marker remove @{ id = 'm1' }).error.code | Should -Be 'E_CONFIRM'; (Invoke-FleetAction marker remove @{ id = 'm1' } -Confirmed).ok | Should -BeTrue }
    It 'dry run does not call handler' { (Invoke-FleetAction marker remove @{ id = 'm1' } -DryRun).result.dryRun | Should -BeTrue }
    It 'handler exceptions become a generic E_INTERNAL' { $e = Invoke-FleetAction boom go; $e.error.code | Should -Be 'E_INTERNAL'; $e.error.message | Should -Not -Match 'kaboom' }
    It 'keys actions by app: same noun verb in two apps' {
        Register-FleetAction -App other -Noun marker -Verb add -ArgsSchema @{ type = 'object'; properties = @{ clip = @{ type = 'string' } } } -Handler { param($a) @{ markerId = 'other' } }
        (Invoke-FleetAction marker add @{ clip = 'c' } -App other).result.markerId | Should -Be 'other'
        (Invoke-FleetAction marker add @{ clip = 'c' } -App demo).result.markerId | Should -Be 'm_c_0'
        (Invoke-FleetAction marker add @{ clip = 'c' }).error.message | Should -Match 'more than one app'
        @(Get-FleetAction).Count | Should -Be 4
    }
}
Describe 'CLI' {
    It 'parses noun verb and kebab args' { $p = ConvertFrom-FleetArgs @('marker', 'add', '--clip-id', 'c1', '--loud', '--json'); $p.Noun | Should -Be 'marker'; $p.Args.clipId | Should -Be 'c1'; $p.Args.loud | Should -BeTrue; $p.Json | Should -BeTrue }
    It 'sets exit code and prints JSON' { $o = Invoke-FleetCli -App demo -Argv @('marker', 'add', '--clip', 'c9', '--json'); $LASTEXITCODE | Should -Be 0; ($o | ConvertFrom-Json).result.markerId | Should -Be 'm_c9_0' }
    It 'commands --json lists actions (help is an alias)' { (Invoke-FleetCli @('help') | ConvertFrom-Json).result.Count | Should -Be 3; $o = Invoke-FleetCli @('commands', '--json'); ($o | ConvertFrom-Json).result.Count | Should -Be 3 }
    It '--out writes UTF-8 without BOM' {
        $f = Join-Path ([IO.Path]::GetTempPath()) "fa-$([guid]::NewGuid()).json"
        Invoke-FleetCli @('marker', 'add', '--clip', 'c1', '--out', $f) | Out-Null
        $b = [IO.File]::ReadAllBytes($f); $b[0] | Should -Be ([byte][char]'{'); Remove-Item $f
    }
    It 'boolean string coerces' { (Invoke-FleetAction marker add @{ clip = 'c'; loud = 'true' }).ok | Should -BeTrue }
}
Describe 'Invoke-FleetJob' {
    It 'chains step results with per-step confirm' {
        $job = '{"version":1,"steps":[{"id":"a","app":"demo","noun":"marker","verb":"add","args":{"clip":"c1"}},{"id":"b","app":"demo","noun":"marker","verb":"remove","confirm":true,"args":{"id":"${steps.a.result.markerId}"}}]}' | ConvertFrom-Json
        $e = Invoke-FleetJob $job; $e.ok | Should -BeTrue; $e.result.steps[1].envelope.result.removed | Should -Be 'm_c1_0'
    }
    It 'destructive step without its own confirm is refused' {
        $job = '{"version":1,"steps":[{"app":"demo","noun":"marker","verb":"remove","args":{"id":"m"}}]}' | ConvertFrom-Json
        (Invoke-FleetJob $job).error.code | Should -Be 'E_CONFIRM'
    }
    It 'uses the step app field' {
        Register-FleetAction -App other -Noun marker -Verb add -ArgsSchema @{ type = 'object'; properties = @{ clip = @{ type = 'string' } } } -Handler { param($a) @{ markerId = 'other' } }
        $job = '{"version":1,"steps":[{"app":"other","noun":"marker","verb":"add","args":{"clip":"c"}}]}' | ConvertFrom-Json
        (Invoke-FleetJob $job).result.steps[0].envelope.result.markerId | Should -Be 'other'
    }
    It 'stops on first failure' {
        $job = '{"version":1,"steps":[{"app":"demo","noun":"boom","verb":"go"},{"app":"demo","noun":"marker","verb":"add","args":{"clip":"x"}}]}' | ConvertFrom-Json
        $e = Invoke-FleetJob $job; $e.ok | Should -BeFalse; @($e.steps).Count | Should -Be 1
    }
    It 'bad references and malformed steps stay inside the envelope' {
        $job = '{"version":1,"steps":[{"app":"demo","noun":"marker","verb":"add","args":{"clip":"${steps.nope.result.x}"}}]}' | ConvertFrom-Json
        $e = Invoke-FleetJob $job; $e.ok | Should -BeFalse; $e.error.code | Should -Be 'E_ARGS'
        $e2 = Invoke-FleetJob ('{"version":1,"steps":[{"app":"demo","noun":"marker","verb":"add","args":[1,2]}]}' | ConvertFrom-Json); $e2.ok | Should -BeFalse
        (Invoke-FleetJob ([pscustomobject]@{ nothing = 1 })).ok | Should -BeFalse
    }
    It 'continue-on-error with some successes is E_PARTIAL (exit 6) with per-step results' {
        $job = '{"version":1,"steps":[{"app":"demo","noun":"boom","verb":"go"},{"app":"demo","noun":"marker","verb":"add","args":{"clip":"x"}}]}' | ConvertFrom-Json
        $e = Invoke-FleetJob $job -ContinueOnError; $e.error.code | Should -Be 'E_PARTIAL'; Get-FleetExitCode $e | Should -Be 6; @($e.steps).Count | Should -Be 2; $e.steps[1].envelope.ok | Should -BeTrue
    }
    It 'dry run validates every step without running handlers' {
        $job = '{"version":1,"steps":[{"app":"demo","noun":"marker","verb":"remove","args":{"id":"m"}}]}' | ConvertFrom-Json
        $e = Invoke-FleetJob $job -DryRun; $e.ok | Should -BeTrue; $e.result.steps[0].envelope.result.destructive | Should -BeTrue
    }
    It 'rejects shapes outside job.schema.json' {
        (Invoke-FleetJob ('{"version":1,"steps":[{"app":"demo","noun":"marker","verb":"add","run":"x"}]}' | ConvertFrom-Json)).error.message | Should -Match 'unknown step key'
        (Invoke-FleetJob ('{"version":1,"extra":1,"steps":[]}' | ConvertFrom-Json)).error.message | Should -Match 'unknown job key'
        (Invoke-FleetJob ('{"version":1,"steps":[{"id":"a","app":"demo","noun":"marker","verb":"add"},{"id":"a","app":"demo","noun":"marker","verb":"add"}]}' | ConvertFrom-Json)).error.message | Should -Match 'duplicate'
        (Invoke-FleetJob ('{"version":1,"steps":[{"app":"demo","noun":"marker","verb":"remove","confirm":"yes"}]}' | ConvertFrom-Json)).error.code | Should -Be 'E_ARGS'
    }
    It 'reads a job file from disk (example-job.json)' {
        $e = Invoke-FleetJob (Join-Path $PSScriptRoot '..\example-job.json'); $e.ok | Should -BeTrue
    }
    It 'rejects other versions' { (Invoke-FleetJob ([pscustomobject]@{ version = 2; steps = @() })).error.code | Should -Be 'E_ARGS' }
}
Describe 'HTTP' {
    It 'routes POST noun/verb' { $r = Resolve-FleetHttpRequest POST '/api/v1/marker/add' $Hd '{"clip":"c2"}' 8900 $Tok; $r.Status | Should -Be 200; $r.Body.result.markerId | Should -Be 'm_c2_0' }
    It 'lists actions' { (Resolve-FleetHttpRequest GET '/api/v1/actions' $Hd '' 8900 $Tok).Status | Should -Be 200 }
    It 'rejects bad token, host, origin' {
        (Resolve-FleetHttpRequest POST '/api/v1/marker/add' @{ Host = '127.0.0.1:8900'; Authorization = 'Bearer x' } '{}' 8900 $Tok).Status | Should -Be 401
        (Resolve-FleetHttpRequest POST '/api/v1/marker/add' @{ Host = 'evil.test:8900'; Authorization = "Bearer $Tok" } '{}' 8900 $Tok).Status | Should -Be 403
        (Resolve-FleetHttpRequest POST '/api/v1/marker/add' ($Hd + @{ Origin = 'http://evil.test' }) '{}' 8900 $Tok).Status | Should -Be 403
    }
    It 'missing token is rejected without reading the body' {
        $script:read = $false
        $r = Invoke-FleetHttpCore -Method POST -Path '/api/v1/marker/add' -Headers @{ Host = '127.0.0.1:8900' } -ContentLength 10 -ReadBody { $script:read = $true; '{}' } -Port 8900 -Token $Tok
        $r.Status | Should -Be 401; $script:read | Should -BeFalse
    }
    It 'oversized, chunked and unknown-length bodies are rejected unread' {
        $script:read = $false; $rb = { $script:read = $true; '{}' }
        (Invoke-FleetHttpCore -Method POST -Path '/api/v1/marker/add' -Headers $Hd -ContentLength 2MB -ReadBody $rb -Port 8900 -Token $Tok).Status | Should -Be 413
        (Invoke-FleetHttpCore -Method POST -Path '/api/v1/marker/add' -Headers $Hd -ContentLength 5 -Chunked -ReadBody $rb -Port 8900 -Token $Tok).Status | Should -Be 411
        (Invoke-FleetHttpCore -Method POST -Path '/api/v1/marker/add' -Headers $Hd -ContentLength -1 -ReadBody $rb -Port 8900 -Token $Tok).Status | Should -Be 411
        $script:read | Should -BeFalse
    }
    It 'bounded reader refuses lengths over the cap' {
        $ms = New-Object IO.MemoryStream (,[byte[]](1..10)); { Read-FleetBoundedBody $ms 10 -Max 5 } | Should -Throw
        $ms2 = New-Object IO.MemoryStream (,[Text.Encoding]::ASCII.GetBytes('{"a":1}')); Read-FleetBoundedBody $ms2 7 | Should -Be '{"a":1}'
    }
    It 'exceptions in the HTTP path stay inside the envelope' {
        $r = Invoke-FleetHttpCore -Method POST -Path '/api/v1/marker/add' -Headers $Hd -ContentLength 5 -ReadBody { throw 'io' } -Port 8900 -Token $Tok
        $r.Status | Should -Be 400; $r.Body.ok | Should -BeFalse
        $r2 = Invoke-FleetHttpCore -Method POST -Path '/api/v1/marker/add' -Headers $null -Port 8900 -Token $Tok
        $r2.Status | Should -BeIn 401, 500; $r2.Body.ok | Should -BeFalse
        (Resolve-FleetHttpRequest POST '/api/v1/boom/go' $Hd '' 8900 $Tok).Status | Should -Be 500
    }
    It 'job route: per-step confirm' {
        $b = '{"version":1,"steps":[{"app":"demo","noun":"marker","verb":"remove","args":{"id":"m"}}]}'
        (Resolve-FleetHttpRequest POST '/api/v1/job' $Hd $b 8900 $Tok).Status | Should -Be 409
        (Resolve-FleetHttpRequest POST '/api/v1/job' $Hd ($b -replace '"args"', '"confirm":true,"args"') 8900 $Tok).Status | Should -Be 200
    }
    It 'destructive needs confirm:true' {
        (Resolve-FleetHttpRequest POST '/api/v1/marker/remove' $Hd '{"id":"m"}' 8900 $Tok).Status | Should -Be 409
        (Resolve-FleetHttpRequest POST '/api/v1/marker/remove' $Hd '{"id":"m","confirm":true}' 8900 $Tok).Status | Should -Be 200
    }
    It 'listener prefix is exactly 127.0.0.1' {
        $l = New-FleetHttpListener -Port 8901; @($l.Prefixes) | Should -Be @('http://127.0.0.1:8901/'); { Assert-FleetListenerPrefix $l } | Should -Not -Throw
        $l2 = New-Object System.Net.HttpListener; $l2.Prefixes.Add('http://+:8902/'); { Assert-FleetListenerPrefix $l2 } | Should -Throw
    }
    It 'real listener: closes the response on reject and on success' {
        $port = 8903; $mod = (Get-Module FleetAction).Path
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($mod, $port, $tok)
            Import-Module $mod; Set-FleetActionLogRoot ''
            Register-FleetAction -App demo -Noun ping -Verb go -Handler { @{ pong = 1 } }
            $l = New-FleetHttpListener -Port $port; $l.Start()
            try { for ($i = 0; $i -lt 2; $i++) { Invoke-FleetHttpAction -Context $l.GetContext() -Port $port -Token $tok -App demo } } finally { $l.Close() }
        }).AddArgument($mod).AddArgument($port).AddArgument($Tok)
        $h = $ps.BeginInvoke(); Start-Sleep -Milliseconds 500
        try {
            $wc = New-Object Net.WebClient
            $code = 0; try { $wc.UploadString("http://127.0.0.1:$port/api/v1/ping/go", '{}') } catch { $code = [int]$_.Exception.InnerException.Response.StatusCode }
            $code | Should -Be 401
            $wc.Headers['Authorization'] = "Bearer $Tok"
            ($wc.UploadString("http://127.0.0.1:$port/api/v1/ping/go", '{}') | ConvertFrom-Json).result.pong | Should -Be 1
        } finally { [void]$h.AsyncWaitHandle.WaitOne(3000); $ps.Dispose() }
    }
}
Describe 'Stable IDs' {
    It 'New-FleetId makes kind_32hex and Test-FleetId checks it' {
        $id = New-FleetId -Kind clip; $id | Should -Match '^clip_[0-9a-f]{32}$'; Test-FleetId $id | Should -BeTrue
        Test-FleetId 'Clip_x' | Should -BeFalse; { New-FleetId -Kind 'Bad Kind' } | Should -Throw
    }
}
Describe 'Session token' {
    It 'is 64 hex chars, file matches, and is removed on stop' {
        $root = Join-Path ([IO.Path]::GetTempPath()) "fa-$([guid]::NewGuid())"
        $t = New-FleetSessionToken -App demo -Root $root; $t | Should -Match '^[0-9a-f]{64}$'
        $p = Get-FleetSessionTokenPath demo $root
        [IO.File]::ReadAllText($p) | Should -Be $t
        Remove-FleetSessionToken -App demo -Root $root; Test-Path $p | Should -BeFalse; Remove-Item $root -Recurse
    }
    It 'Windows: owner-only ACL with inheritance off' -Skip:($env:OS -ne 'Windows_NT') {
        $root = Join-Path ([IO.Path]::GetTempPath()) "fa-$([guid]::NewGuid())"
        New-FleetSessionToken -App demo -Root $root | Out-Null
        $acl = Get-Acl (Get-FleetSessionTokenPath demo $root)
        $acl.AreAccessRulesProtected | Should -BeTrue
        $rules = @($acl.Access); $rules.Count | Should -Be 1
        $rules[0].IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value | Should -Be ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        Remove-Item $root -Recurse -Force
    }
    It 'non-Windows: mode 600' -Skip:($env:OS -eq 'Windows_NT') {
        $root = Join-Path ([IO.Path]::GetTempPath()) "fa-$([guid]::NewGuid())"
        New-FleetSessionToken -App demo -Root $root | Out-Null
        (& stat -c '%a' (Get-FleetSessionTokenPath demo $root)) | Should -Be '600'; Remove-Item $root -Recurse
    }
}
}
