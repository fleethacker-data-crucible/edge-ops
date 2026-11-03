# fleet-action (v0.2.0, reference implementation)

Shared action dispatcher for the Fleet Action Framework (spec: comms `proposals/fleet-action-framework/README.md`, standard: comms #68). Windows PowerShell 5.1, no admin, offline, loopback only, MIT. Vendor it into an app like `FleetPort.psm1`.

## Use in an app

```powershell
Import-Module "$PSScriptRoot\FleetAction.psm1"
Register-FleetAction -App capstan -Noun marker -Verb add -Description 'Add a marker' `
  -ArgsSchema @{ type='object'; required=@('clip'); properties=@{ clip=@{type='string'}; at=@{type='integer'; default=0} } } `
  -Handler { param($a) Add-CapstanMarker -Clip $a.clip -At $a.at }

# CLI entry (capstan.ps1):   Invoke-FleetCli -App capstan -Argv $args; exit $LASTEXITCODE
#   capstan.bat marker add --clip c1 --at 5 --json
#   capstan.bat help                     (discovery, JSON)
#   capstan.bat marker remove --id m1 --yes

# HTTP (inside the existing HttpListener loop):
$l   = New-FleetHttpListener -Port $port          # binds exactly http://127.0.0.1:<port>/
$tok = New-FleetSessionToken -App capstan        # %LOCALAPPDATA%\FleetHacker\capstan\session.token
try { $l.Start(); while ($l.IsListening) { $ctx = $l.GetContext()
  if ($ctx.Request.Url.AbsolutePath -like '/api/v1/*') { Invoke-FleetHttpAction -Context $ctx -Port $port -Token $tok -App capstan; continue }
  # ... the app's own routes ...
} } finally { $l.Close(); Remove-FleetSessionToken -App capstan }

# Job file:
Invoke-FleetJob -Job .\example-job.json     # destructive steps need "confirm": true on that step
```

## Contract

- Envelope: `{ ok, action, v: 1, result | error{code,message}, warnings }`.
- Exit / HTTP: 0/200 OK, 2/400 E_ARGS, 3/404 E_NOTFOUND, 4/409 E_CONFIRM, 5/401 E_AUTH, 1/500 E_INTERNAL, 2/411 E_LENGTH, 2/413 E_TOOLARGE.
- HTTP: `POST /api/v1/<noun>/<verb>` (JSON args, `"confirm": true` for destructive; in jobs, per step), `GET /api/v1/actions`, `POST /api/v1/job`. Requires `Authorization: Bearer <session token>`, Host `127.0.0.1:<port>` or `localhost:<port>`, and same-origin `Origin` if sent. No CORS headers.
- `--out <file>` writes UTF-8 without BOM. Args: JSON Schema subset (type, required, properties, enum, default); unknown args rejected.
- Jobs: JSON, `version: 1`, steps `{id, app, noun, verb, args}`, only `${steps.<id>.result.<field>}` substitution, stop on first failure.

## Hardening rules

- **Bind exactly `http://127.0.0.1:<port>/`.** Never `+`, `*`, `localhost` or a hostname as the listener prefix. Use `New-FleetHttpListener`; if an app builds its own listener, call `Assert-FleetListenerPrefix` before `Start()`.
- **The session token is full authority** over the app. Anyone who can read it can run every action, including destructive ones.
- **confirm / `--yes` is an accident guard, not a security control.** It stops a script or agent from deleting by mistake; it does not prove a human agreed. Real human confirmation would have to happen on the server side (a GUI prompt the app shows) and is planned for a later version.
- **Token file:** created empty, then locked before the token is written. On Windows: inheritance off, owner and a single FullControl rule for the current user only. Elsewhere: `chmod 600`. Delete it when the app stops (`Remove-FleetSessionToken` in a `finally`).
- **Request order:** Host, Origin and Bearer token are checked before the body is read. Bodies need a `Content-Length` (chunked or unknown length gets 411) and are capped at 1 MB (413); the body is read with a bounded buffer. `Invoke-FleetHttpAction` always closes the response.
- **Arguments:** anything the schema doesn't declare is rejected, and scalar-typed args must be single values.
- **Errors:** `E_INTERNAL` returns a generic message; details go only to `%LOCALAPPDATA%\FleetHacker\<app>\actions.log`. Destructive calls are logged there too.
- **Job values are untrusted.** `${steps.<id>.result.<field>}` copies text from an earlier step's result into a later step's args. Handlers must validate those values like any other input (paths, IDs, URLs).
- Actions are keyed by app + noun + verb. Calls without an app work only when the noun + verb is unique.

## Tests

`Invoke-Pester tools/fleet-action/tests` (Pester 5): 36 tests (one is Windows-only, one non-Windows-only), including a real `HttpListener` round trip on 127.0.0.1:8903.

Not in v0.2: YAML jobs, `fleet.ps1` cross-app dispatcher, MCP generation, GUI parity test, server-side human confirmation.
