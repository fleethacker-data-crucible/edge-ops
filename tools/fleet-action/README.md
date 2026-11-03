# fleet-action (v0.1.0, reference implementation)

Shared action dispatcher for the Fleet Action Framework (spec: comms `proposals/fleet-action-framework/README.md`, standard: comms #68). Windows PowerShell 5.1, no admin, offline, loopback only, MIT. Vendor it into an app like `FleetPort.psm1`.

## Use in an app

```powershell
Import-Module "$PSScriptRoot\FleetAction.psm1"
Register-FleetAction -App capstan -Noun marker -Verb add -Description 'Add a marker' `
  -ArgsSchema @{ type='object'; required=@('clip'); properties=@{ clip=@{type='string'}; at=@{type='integer'; default=0} } } `
  -Handler { param($a) Add-CapstanMarker -Clip $a.clip -At $a.at }

# CLI entry (capstan.ps1):   Invoke-FleetCli -Argv $args; exit $LASTEXITCODE
#   capstan.bat marker add --clip c1 --at 5 --json
#   capstan.bat help                     (discovery, JSON)
#   capstan.bat marker remove --id m1 --yes

# HTTP (inside the existing HttpListener loop):
$tok = New-FleetSessionToken -App capstan        # %LOCALAPPDATA%\FleetHacker\capstan\session.token
if ($ctx.Request.Url.AbsolutePath -like '/api/v1/*') { Invoke-FleetHttpAction -Context $ctx -Port $port -Token $tok; continue }

# Job file:
Invoke-FleetJob -Job .\example-job.json -Confirm
```

## Contract

- Envelope: `{ ok, action, v: 1, result | error{code,message}, warnings }`.
- Exit / HTTP: 0/200 OK, 2/400 E_ARGS, 3/404 E_NOTFOUND, 4/409 E_CONFIRM, 5/401 E_AUTH, 1/500 E_INTERNAL.
- HTTP: `POST /api/v1/<noun>/<verb>` (JSON args, `"confirm": true` for destructive), `GET /api/v1/actions`, `POST /api/v1/job`. Requires `Authorization: Bearer <session token>`, Host `127.0.0.1:<port>` or `localhost:<port>`, and same-origin `Origin` if sent. No CORS headers.
- `--out <file>` writes UTF-8 without BOM. Args: JSON Schema subset (type, required, properties, enum, default); unknown args rejected.
- Jobs: JSON, `version: 1`, steps `{id, app, noun, verb, args}`, only `${steps.<id>.result.<field>}` substitution, stop on first failure.

## Tests

`Invoke-Pester tools/fleet-action/tests` (Pester 5): 21 tests, passing on pwsh 7 (Linux). Not yet run on Windows PowerShell 5.1.

Not in v0.1: YAML jobs, `fleet.ps1` cross-app dispatcher, MCP generation, GUI parity test.
