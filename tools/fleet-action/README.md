# fleet-action (v0.3.0, reference copy)

> The canonical module now lives in [fleethacker-data-crucible/fleet-action-baseline](https://github.com/fleethacker-data-crucible/fleet-action-baseline) (being built). This folder is a reference copy; vendor from the baseline repo once it ships.

Shared action dispatcher for the Fleet Action Framework (spec: comms `proposals/fleet-action-framework/README.md`, standard: comms #68). Windows PowerShell 5.1, no admin, offline, loopback only, MIT. Vendor it into an app like `FleetPort.psm1`.

## Use in an app

```powershell
Import-Module "$PSScriptRoot\FleetAction.psm1"
Register-FleetAction -App capstan -Noun marker -Verb add -Description 'Add a marker' `
  -ArgsSchema @{ type='object'; required=@('clip'); properties=@{ clip=@{type='string'}; at=@{type='integer'; default=0} } } `
  -Handler { param($a) Add-CapstanMarker -Clip $a.clip -At $a.at }

# CLI entry (capstan.ps1):   Invoke-FleetCli -App capstan -Argv $args; exit $LASTEXITCODE
#   capstan.bat marker add --clip c1 --at 5 --json
#   capstan.bat commands --json          (discovery; `help` is an alias)
#   See app-cli.example.ps1: powershell.exe -NoProfile -ExecutionPolicy Bypass -File, fails fast unless PS 5.1
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
- Exit / HTTP: 0/200 OK, 2/400 E_ARGS, 3/404 E_NOTFOUND, 4/409 E_CONFIRM, 5/401 E_AUTH (missing/bad token), 5/403 E_FORBIDDEN (Host/Origin), 6/207 E_PARTIAL (job with --continue-on-error, some steps failed), 1/500 E_INTERNAL, 2/411 E_LENGTH, 2/413 E_TOOLARGE.
- HTTP: `POST /api/v1/<noun>/<verb>` (JSON args, `"confirm": true` for destructive; in jobs, per step), `GET /api/v1/actions`, `POST /api/v1/job`. Requires `Authorization: Bearer <session token>`, Host `127.0.0.1:<port>` or `localhost:<port>`, and same-origin `Origin` if sent. No CORS headers.
- `--out <file>` writes UTF-8 without BOM. Args: JSON Schema subset (type, required, properties, enum, default); unknown args rejected.
- `warnings` is always present. `--dry-run` validates and returns `{dryRun, destructive, args}` without running the handler; in a dry-run job, `${steps...}` references resolve to empty strings.
- Job results: `result.steps[]` (or `steps[]` on failure) = `{ id, envelope }` per step that ran.
- Jobs: JSON only (`job.schema.json`, v1, no YAML), `version: 1`, steps `{id, app, noun, verb, args}`, only `${steps.<id>.result.<field>}` substitution, stop on first failure.

## Hardening rules

- **Bind exactly `http://127.0.0.1:<port>/`.** Never `+`, `*`, `localhost` or a hostname as the listener prefix. Use `New-FleetHttpListener`; if an app builds its own listener, call `Assert-FleetListenerPrefix` before `Start()`.
- **The session token is full authority** over the app. Anyone who can read it can run every action, including destructive ones.
- **confirm / `--yes` is an accident guard, not a security control.** It stops a script or agent from deleting by mistake; it does not prove a human agreed. Real human confirmation would have to happen on the server side (a GUI prompt the app shows) and is planned for a later version.
- **Token file:** created empty, then locked before the token is written. On Windows: inheritance off, owner and a single FullControl rule for the current user only. Elsewhere: `chmod 600`. Delete it when the app stops (`Remove-FleetSessionToken` in a `finally`).
- **Request order:** Host, Origin and Bearer token are checked before the body is read. Bodies need a `Content-Length` (chunked or unknown length gets 411) and are capped at 1 MB (413); the body is read with a bounded buffer. `Invoke-FleetHttpAction` always closes the response.
- **Arguments:** anything the schema doesn't declare is rejected, and scalar-typed args must be single values.
- **Errors:** `E_INTERNAL` returns a generic message; details go only to `%LOCALAPPDATA%\FleetHacker\<app>\actions.log`. Destructive calls are logged there too.
- **Job values are untrusted.** `${steps.<id>.result.<field>}` copies text from an earlier step's result into a later step's args. Handlers must validate those values like any other input (paths, IDs, URLs).
- Stable IDs: `New-FleetId -Kind clip` gives `clip_<32 hex>`. The app that creates an object makes the ID once; it never changes and is stored in the project JSON and passed between apps as-is. `Test-FleetId` checks the format.
- PS 5.1 JSON: `ConvertFrom-Json` returns PSCustomObject; the module converts with `PSObject.Properties` before using hashtable methods, and every `ConvertTo-Json` call passes `-Depth 20`.
- Token in the served page: inject it into a JS variable or `<meta>` only after the Host/Origin checks pass, with `Cache-Control: no-store` (API responses already send it); never in a URL, a log, a visible/focusable element or `data-action` markup. A new token is written on every start.
- Logs: destructive calls log the action and argument names only, never values or the token.
- Parameter is `-Confirmed` (not `-Confirm`, which collides with ShouldProcess).
- Actions are keyed by app + noun + verb. Calls without an app work only when the noun + verb is unique.

## Tests

`Invoke-Pester tools/fleet-action/tests` (Pester 5): 41 tests (one is Windows-only, one non-Windows-only), including a real `HttpListener` round trip on 127.0.0.1:8903.

Not in v0.3: YAML jobs (v2 at the earliest), `fleet.ps1` cross-app dispatcher, MCP generation, GUI parity test, server-side human confirmation.
