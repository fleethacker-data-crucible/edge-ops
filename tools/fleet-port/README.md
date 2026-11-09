# FleetPort

Port blocks with self-detection for FleetHacker tools, and on-demand starting of the shared services they depend on (Windows PowerShell 5.1). Rules: [PORTS.md](../../PORTS.md#self-detection-and-policies).

```powershell
Import-Module "$PSScriptRoot\FleetPort.psm1"
$r = Resolve-FleetPort -Tool 'lasso' -Version $version          # walks 8765-8766 and applies 'reuse'
if ($r.Action -eq 'Reuse') { Start-Process $r.Url; exit 0 }      # same version already running
$listener = $r.Listener                                          # started on http://localhost:<port>/
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $h = Invoke-FleetIdEndpoint -Context $ctx -Tool 'lasso' -Version $version -Path $PSCommandPath
    if ($h -eq 'shutdown') { break }                             # release leases, remove .pid, exit
    if ($h) { continue }
    # ... the tool's own routes ...
}
```

## Stopping an older copy on an http.sys port

HttpListener ports are owned by PID 4 (System), so `Stop-FleetInstance` cannot prove ownership with `Get-NetTCPConnection`. Instead it reads `netsh http show servicestate view=requestq`. That query is read-only and **works for a standard (non-admin) user**: Zombie Admin's capture on Windows PowerShell 5.1, as a standard user on en-US Windows, exited 0 with the full English layout (`tests/netsh/requestq-en-real-8845.txt`).

When an older copy ignores `POST /__fleethacker/shutdown`, a well-formed older copy **is force-stopped** when all four proof conditions pass:

1. Graceful shutdown was tried first and the grace period ran out.
2. The reported path is an exact, absolute `-File` or executable match.
3. `netsh http show servicestate view=requestq` shows exactly one request queue with a URL on the port. Every URL it has on that port is plain `http` on a loopback host with the path `/`, and its only process is the self-reported pid. Loopback means `localhost`, `127.0.0.1` or `[::1]`. The IP-bound form `HTTP://127.0.0.1:<port>:127.0.0.1/` (host:port:ip, which TalkForge registers) is parsed explicitly and counts as loopback only when the bound ip is `127.0.0.1` or `::1`.
4. `/__fleethacker/id` re-checked on the port still reports the same tool and pid.

Only when the proof is **uncertain** does the launcher refuse, kill nothing, and stop with:

    An older <Tool> v<X> is still running; close its window and relaunch.

Uncertain means any of these: the queue also registers an extra prefix on the port (for example `http://localhost:<port>/legacy/`), a `+`, `*` or non-loopback host or bound ip, a URL line that can't be parsed, more than one queue on the port, an empty queue or more than one process, a queue pid that isn't the self-reported pid, a failed id re-check, or netsh output that isn't the English layout (another language, error text, non-zero exit).

The fixtures in `tests/netsh/` are the real capture plus one-edit variants of it; [tests/netsh/README.md](tests/netsh/README.md) lists each edit.

## Starting a shared service

> `Start-FleetService` makes sure a shared local service an app depends on is running: it reuses a verified one, or starts it once.

Fleet apps depend on shared local services: Fairlead (the model router, `127.0.0.1:8776`) and the TalkForge speech server (`127.0.0.1:25009`). The decision of 2026-11-08 is that each app starts what it needs, when it needs it, through this one helper instead of its own copy. No app is the launcher hub, Lazarette included. Ports: [PORTS.md](../../PORTS.md#starting-shared-services).

**Status:** new. Semaphore (`Start-SemTalkForge`, and `Start-SemFairlead` on its pending branch) and Lazarette (`Start-LazaretteTalkForge` in `lib/server/Stark.ps1`) still start these services themselves. Moving each app to this helper is a follow-up in that app's repo.

### Run

```powershell
Import-Module "$PSScriptRoot\FleetPort.psm1"

# Fairlead: shared tray app, started detached; it keeps running when this app exits.
$r = Start-FleetService -Name fairlead -WaitSeconds 40
if ($r.State -ne 'running') { Write-Log $r.Message }      # 'starting' or 'unavailable', with a sentence for the person

# TalkForge: the token goes only into the child's environment. Drop your copy straight after.
$r = Start-FleetService -Name talkforge -Folder $settings.TalkForgeFolder -Environment @{ TALKFORGE_TOKEN = $token } -WaitSeconds 20
$token = $null

# When this app stops: end the TalkForge it started (one started by another app or by hand is never touched).
[void](Stop-FleetServiceChild -Name talkforge)

# Show the state without starting anything (for a status light or a settings page).
(Get-FleetServiceState -Name talkforge).State              # running | starting | stopped | unavailable
```

| Parameter | Meaning |
|---|---|
| `-Name` | `fairlead` or `talkforge` |
| `-Folder` | The service's folder, from the app's settings. When given, it is used exactly, with no fallback. When left out, the helper looks for `<Name>` next to the calling app (beside the caller's folder and beside its parent, since entry scripts often live in `server\` or `src\`), then in `%USERPROFILE%\Projects\<Name>`. `-CallerRoot` overrides the caller's folder. |
| `-Port` | Default: the service's port from the table below |
| `-Environment` | Variables for a `child` service only (the TalkForge token). Refused for `shell` services. |
| `-WaitSeconds` | Wait up to this long for `running` after a start (default 0: return `starting` at once) |
| `-StateDirectory` | Where starts are recorded (default `%LOCALAPPDATA%\FleetHacker\services`; tests pass their own) |

The result is `{ State; Message; StartedHere; Name; Port; Url; Pid; Version; Folder; Reason }`. `State` is `running`, `starting` or `unavailable` (`Get-FleetServiceState` can also return `stopped`). `Reason` is a short code: `port-taken`, `not-found`, `no-secret`, `no-runtime`, `exited`, `timeout`, `start-failed`, `bad-call` or `busy`. Expected failures do not throw.

### Requirements

| Needs | Yes/No |
|---|---|
| Windows PowerShell 5.1 | Yes |
| Admin rights | No |
| Installs / third-party runtimes | None for the helper. TalkForge itself needs Node.js 18+ on `PATH` (`Reason = 'no-runtime'` without it). |
| Network access | No (loopback only) |
| Runtime C# compile (Add-Type) | No |

### What it does

| Service | Port | Started as | Outlives the caller |
|---|---|---|---|
| `fairlead` | 8776 | `powershell.exe -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File <Fairlead>\scripts\Start-Fairlead.ps1 --no-browser`, through the shell (`-Port <p>` is added only for a port other than 8776) | yes |
| `talkforge` | 25009 | `node <TalkForge>\tools\talkforge.mjs serve --port <p> --idle-timeout 30`, a hidden child with stdout and stderr redirected and drained | no: it stops after 30 idle minutes, or with `Stop-FleetServiceChild` |

Every call:

1. **Probes the port.** When it is busy, the program there must answer `GET /__fleethacker/id` with the service's tool id and a pid that owns the listening port (`Get-NetTCPConnection`, or `netstat -ano` when that cmdlet is missing). When it reports a `path`, that path must be absolute and exactly equal the pid's executable, PowerShell `-File` script or node script. Never a substring match. For TalkForge the path must also end in `tools\talkforge.mjs`, so TalkForge's page server, which also reports `tool: talkforge`, is not mistaken for the speech server.
2. **Never starts on a port another program holds.** A foreign program, another Fleet tool, or something that claims to be the service but fails a check gives `unavailable` / `port-taken`. Nothing is started or stopped.
3. **Never starts twice.** The decision is taken under a named mutex (`Local\FleetHacker.FleetService.<name>.<port>`), and each start is recorded in `<StateDirectory>\<name>-<port>.json`. Every app, runspace and process reads that record, so a start in the last 60 s (Fairlead) or 45 s (TalkForge) is reported as `starting` instead of being repeated. When a recorded start never answers, or a TalkForge child exits first, the next call reports `unavailable` (`timeout` or `exited`) once and clears the record, and the call after that tries again.
4. **Starts it hidden**, with the start command from the table in `FleetPort.psm1` (`$script:FleetServices`: folder name, marker file, port, tool id, start command, launch kind). A new service is one more entry there.

### How it works

- **`shell` (Fairlead):** `UseShellExecute`, so the new process inherits no handle of the caller. That is why it outlives the caller, and why a long-running tray app does not hold the caller's console or pipes open. The shell cannot set environment variables, so the service inherits the caller's environment. Do not keep secrets in your process environment when you start a `shell` service (Fairlead reads its own config and needs none).
- **`child` (TalkForge):** a hidden child, `CreateNoWindow`, stdout and stderr redirected and read with no handler (the lines are dropped; without this, node blocks once a pipe fills), stdin closed. Before `-Environment` is applied, its environment loses `TALKFORGE_TOKEN`, `TALKFORGE_TOKEN_FILE`, `TALKFORGE_LAZARETTE_ITEM` and any of the caller's variables whose names look secret (`TOKEN`, `SECRET`, `PASSWORD`, `PASSPHRASE`, `API_KEY`, `*_KEY`, `CREDENTIAL`). The process handle is kept in the module, so the output stays drained and `Stop-FleetServiceChild` can end exactly that process, and never a reused pid.
- **Data:** only the start record (`name`, `port`, `pid`, `startedAt`, the caller's pid) in `%LOCALAPPDATA%\FleetHacker\services`. Nothing leaves the machine.

### Development and tests

`tests/FleetService.Tests.ps1` (Pester 5, Windows PowerShell 5.1) writes a fake Fairlead (a PowerShell TcpListener script) and a fake TalkForge (a node script) to `TestDrive` and runs them on free ports the OS hands out. It never touches the real Fairlead on 8776, TalkForge on 25009, or anything else that is running. The tests cover: a port held by a foreign program, another tool, a wrong pid and a wrong path; four runspaces asking at once (one start); a start from a process that then exits (Fairlead keeps running); the TalkForge token kept off the command line and out of the caller's other secrets; draining 2 MB of child output; a child that exits while starting; and TalkForge's page server on the speech port. The TalkForge tests are skipped when node is not on `PATH`.

### Security notes

- The helper checks who holds the port at the moment it is called. An app that then sends a key or token should go ahead only on `State -eq 'running'`, and keep its own `/__fleethacker/id` check right before sending (Semaphore's `Test-SemAiIdentity`, Lazarette's Fairlead check), because the port can change hands in between.
- The token never appears on a command line, in the start record, or in a message. Clear your own copy after the call.
- Nothing is ever stopped except a `child` this process started itself.

Tests: `Invoke-Pester tools/fleet-port/tests` (Pester 5; `FleetPort.Tests.ps1` uses scratch ports 8834-8859, `FleetService.Tests.ps1` uses free ports from the OS).
