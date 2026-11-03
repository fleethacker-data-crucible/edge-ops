# Pester 5. Runs on Windows PowerShell 5.1 and pwsh.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\FleetAction.psm1') -Force
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
    Register-FleetAction -App demo -Noun boom -Verb go -Handler { throw 'kaboom' }
}
Describe 'Invoke-FleetAction' {
    It 'runs and returns an ok envelope' { $e = Invoke-FleetAction marker add @{ clip = 'c1'; at = '5' }; $e.ok | Should -BeTrue; $e.result.markerId | Should -Be 'm_c1_5'; $e.action | Should -Be 'demo marker add' }
    It 'applies defaults' { (Invoke-FleetAction marker add @{ clip = 'c1' }).result.markerId | Should -Be 'm_c1_0' }
    It 'rejects missing required' { $e = Invoke-FleetAction marker add @{}; $e.error.code | Should -Be 'E_ARGS'; Get-FleetExitCode $e | Should -Be 2 }
    It 'rejects bad types and unknown args' {
        (Invoke-FleetAction marker add @{ clip = 'c'; at = 'x' }).error.code | Should -Be 'E_ARGS'
        (Invoke-FleetAction marker add @{ clip = 'c'; nope = 1 }).error.message | Should -Match 'unknown'
    }
    It 'unknown action is E_NOTFOUND' { Get-FleetExitCode (Invoke-FleetAction foo bar) | Should -Be 3 }
    It 'destructive needs confirm' { (Invoke-FleetAction marker remove @{ id = 'm1' }).error.code | Should -Be 'E_CONFIRM'; (Invoke-FleetAction marker remove @{ id = 'm1' } -Confirm).ok | Should -BeTrue }
    It 'dry run does not call handler' { (Invoke-FleetAction marker remove @{ id = 'm1' } -DryRun).result.dryRun | Should -BeTrue }
    It 'handler exceptions become E_INTERNAL' { (Invoke-FleetAction boom go).error.message | Should -Be 'kaboom' }
}
Describe 'CLI' {
    It 'parses noun verb and kebab args' { $p = ConvertFrom-FleetArgs @('marker', 'add', '--clip-id', 'c1', '--loud', '--json'); $p.Noun | Should -Be 'marker'; $p.Args.clipId | Should -Be 'c1'; $p.Args.loud | Should -BeTrue; $p.Json | Should -BeTrue }
    It 'sets exit code and prints JSON' { $o = Invoke-FleetCli @('marker', 'add', '--clip', 'c9', '--json'); $LASTEXITCODE | Should -Be 0; ($o | ConvertFrom-Json).result.markerId | Should -Be 'm_c9_0' }
    It 'help lists actions' { $o = Invoke-FleetCli @('help'); ($o | ConvertFrom-Json).result.Count | Should -Be 3 }
    It '--out writes UTF-8 without BOM' {
        $f = Join-Path ([IO.Path]::GetTempPath()) "fa-$([guid]::NewGuid()).json"
        Invoke-FleetCli @('marker', 'add', '--clip', 'c1', '--out', $f) | Out-Null
        $b = [IO.File]::ReadAllBytes($f); $b[0] | Should -Be ([byte][char]'{'); Remove-Item $f
    }
    It 'boolean string coerces' { (Invoke-FleetAction marker add @{ clip = 'c'; loud = 'true' }).ok | Should -BeTrue }
}
Describe 'Invoke-FleetJob' {
    It 'chains step results' {
        $job = '{"version":1,"steps":[{"id":"a","app":"demo","noun":"marker","verb":"add","args":{"clip":"c1"}},{"id":"b","app":"demo","noun":"marker","verb":"remove","args":{"id":"${steps.a.result.markerId}"}}]}' | ConvertFrom-Json
        $e = Invoke-FleetJob $job -Confirm; $e.ok | Should -BeTrue; $e.result.steps[1].envelope.result.removed | Should -Be 'm_c1_0'
    }
    It 'stops on first failure' {
        $job = '{"version":1,"steps":[{"noun":"boom","verb":"go"},{"noun":"marker","verb":"add","args":{"clip":"x"}}]}' | ConvertFrom-Json
        $e = Invoke-FleetJob $job; $e.ok | Should -BeFalse; @($e.steps).Count | Should -Be 1
    }
    It 'rejects other versions' { (Invoke-FleetJob ([pscustomobject]@{ version = 2; steps = @() })).error.code | Should -Be 'E_ARGS' }
}
Describe 'HTTP' {
    It 'routes POST noun/verb' { $r = Resolve-FleetHttpRequest POST '/api/v1/marker/add' $Hd '{"clip":"c2"}' 8900 $Tok; $r.Status | Should -Be 200; $r.Body.result.markerId | Should -Be 'm_c2_0' }
    It 'lists actions' { (Resolve-FleetHttpRequest GET '/api/v1/actions' $Hd '' 8900 $Tok).Status | Should -Be 200 }
    It 'rejects bad token, host, origin' {
        (Resolve-FleetHttpRequest POST '/api/v1/marker/add' @{ Host = '127.0.0.1:8900'; Authorization = 'Bearer x' } '{}' 8900 $Tok).Status | Should -Be 401
        (Resolve-FleetHttpRequest POST '/api/v1/marker/add' @{ Host = 'evil.test:8900'; Authorization = "Bearer $Tok" } '{}' 8900 $Tok).Status | Should -Be 401
        (Resolve-FleetHttpRequest POST '/api/v1/marker/add' ($Hd + @{ Origin = 'http://evil.test' }) '{}' 8900 $Tok).Status | Should -Be 401
    }
    It 'destructive needs confirm:true' {
        (Resolve-FleetHttpRequest POST '/api/v1/marker/remove' $Hd '{"id":"m"}' 8900 $Tok).Status | Should -Be 409
        (Resolve-FleetHttpRequest POST '/api/v1/marker/remove' $Hd '{"id":"m","confirm":true}' 8900 $Tok).Status | Should -Be 200
    }
    It 'session token file is 64 hex chars' {
        $root = Join-Path ([IO.Path]::GetTempPath()) "fa-$([guid]::NewGuid())"
        $t = New-FleetSessionToken -App demo -Root $root; $t | Should -Match '^[0-9a-f]{64}$'
        Get-Content (Join-Path $root 'FleetHacker/demo/session.token') -Raw | Should -Be $t; Remove-Item $root -Recurse
    }
}
}
