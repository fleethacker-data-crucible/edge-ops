# Port registry

**Status: APPROVED (2026-10-25).** The table and policies were approved by Chief of Staff, and MailHawk's move to 8771-8773 by Jeremy. This revision replaces the fallback columns of the earlier 2026-10-25 ruling (Synapse stays on 8767; ARC is gone).

Each tool owns **one small contiguous block** that starts at its default. It moves up inside that block only when a port is busy, and a busy port is first probed to see whether it is **the same tool** (see [Self-detection](#self-detection-and-policies)). If the block is full, the tool stops with a clear error. There is **no random fallback and no OS-ephemeral (port 0) fallback**; the only random range is Data Noodler's site, which the user opts into.

**Rule: never scan into another tool's block.** The blocks below are disjoint (checked by `tools/fleet-port/tests`). The machine-readable copy is [tools/fleet-port/FleetPorts.psd1](tools/fleet-port/FleetPorts.psd1); keep the two in sync.

| Tool | Block | Policy | Override | Notes |
|---|---|---|---|---|
| Phoenix LAI API (OpenAI-compatible `/v1`) | 1234 (1 port) | exclusive | - | LM Studio-compatible on purpose |
| Data Noodler control panel | 8079-8081 | reuse | settings | was fixed 8079 |
| Data Noodler site | 47823 (manual mode) or random **30000-46999** | exempt | settings `portMode` | the only random range; random range narrowed from 10000-65535 |
| Lasso (formerly SnipHero Studio) | 8765-8766 | reuse | `-Port <n>` | was a 100-port scan (8765-8864) then port 0 |
| Synapse (served edition) | **8767** (1 port, fixed) | reuse | `Serve-Synapse.ps1 -Port <n>` | browser data is keyed to the origin, so the port never moves; the standalone HTML still runs from `file://` |
| Lasso dev instance | 8768 (1 port) | restart | `dev\Launch-LocalDev.bat` | was 8790 |
| Keystone | 8769-8770 | reuse | `Launch-Keystone.bat -NoBrowser 8770` | 8770 was the manual alternative |
| MailHawk | **8771-8773** | exclusive | `MailHawk.bat -Port <n>` | moved from 8766 (now inside Lasso's block); holds the Outlook COM lease |
| New tool A / New tool B | 8774-8776 / 8777-8779 | reuse | - | add a row here and in `FleetPorts.psd1` when you take one |
| Phoenix LAI server UI | **8780-8789** | exclusive | - | holds the GPU lease; was 8765-8789 |
| Phoenix LAI client | 8790-8798 | multi | - | several clients may run at once |
| Phoenix LAI dev e2e | 8799 (1 port) | restart | - | test fixture |
| TalkForge static server | 25000-25009 | reuse | `serve-windows.ps1 -Port <n>` | was 25000 up to 65535 |
| Test Chrome debug ports | 9300-9399 (reserved) | - | - | `Start-IsolatedChrome` ([tools/test-harness](tools/test-harness/)); tools must not default here |
| CI-only test ports | 18000-18999 | - | - | e.g. Synapse CI uses 18765 |

## Self-detection and policies

Helper: [tools/fleet-port/FleetPort.psm1](tools/fleet-port/FleetPort.psm1) (`Get-FleetPortBlock`, `Test-FleetSelf`, `Resolve-FleetPort`, `Stop-FleetInstance`, `Invoke-FleetIdEndpoint`).

- **Id endpoint:** every tool answers `GET /__fleethacker/id` on loopback with JSON `{"tool":"<id>","version":"<x.y.z>","pid":<n>,"path":"<script or exe>"}` (`path` is optional and is used only to verify a pid before Stop-Process).
- **Shutdown endpoint:** `POST /__fleethacker/shutdown` with header `X-FleetHacker-Shutdown: 1` asks the tool to exit cleanly (close leases, remove its `.pid` file). Both endpoints require a loopback caller, a loopback `Host` and an `Origin` that is absent or same-origin.
- **Busy port:** probe it. No answer or another tool's id means a foreign program: try the next port in the block. The same tool id means apply that tool's policy:

| Policy | Same version running | Older (or unparseable) version running |
|---|---|---|
| **reuse / restart / exclusive**, when a **newer** copy is running | - | reuse it and log "stale launcher"; never downgrade |
| **reuse** (default for single-user UI tools) | open the browser to it and exit | stop it gracefully, then start on that port |
| **restart** | stop it gracefully, then start | stop it gracefully, then start |
| **multi** | leave it, try the next port | leave it, try the next port |
| **exclusive** (holds a lease) | open the browser to it and exit | clear error; never auto-stop |

- **Stopping:** shutdown endpoint first. Only if the port is still held after the grace period may a tool use `Stop-Process` on the **self-reported pid**, and only when all of these hold: the reported `path` is absolute and normalized (drive or UNC root; values like `powershell` or `tools\x.ps1` are refused); it **exactly** equals (case-insensitive) that pid's `-File` script, parsed from `Win32_Process.CommandLine` with Windows quoting rules, or its `ExecutablePath` for a compiled tool, and never a substring match; and that pid owns the listening port (`Get-NetTCPConnection -LocalPort <p> -State Listen`). Otherwise it refuses with a warning. Tools must report `path` as their absolute `$PSCommandPath` (or exe path).
- **http.sys (PID 4) ports:** an HttpListener port is owned by PID 4 (System), so the pid check above cannot pass. If an older copy on such a port ignores the shutdown request, the launcher shows **"An older &lt;Tool&gt; v&lt;X&gt; is still running; close its window and relaunch."** and exits **without stopping anything**. The only exception is a forced stop where ALL of the following hold:
  1. Graceful shutdown was tried first and the grace period ran out.
  2. The reported `path` is an exact, absolute `-File` or executable match (see the rules above).
  3. The port is owned only by PID 4. In the output of `netsh http show servicestate view=requestq`, exactly one request queue registers a URL on that port, and that URL is exactly `http://localhost:<port>/`. That queue must also list exactly one process, and it must be the self-reported pid.
  4. `/__fleethacker/id` on the port, re-checked right before the kill, still reports the same tool and pid.

  If anything cannot be parsed with certainty, the launcher refuses and uses the message-only path. That covers a non-English netsh layout (only the English layout is understood), a netsh error, access denied or an elevation prompt, an empty queue, more than one queue or process, and a `+`, `*` or IP host on the port. The netsh query is read-only and is run as the current user.

## Port handling standard

Reference: phoenix-lai `src\WebServer.cs` (`StartOnFreePort`) and data-noodler `server\server.ps1`. Snippet: [templates/ports/LoopbackPort.ps1](templates/ports/LoopbackPort.ps1).

1. **Listener:** HttpListener on `http://localhost:<port>/` (or TcpListener on `IPAddress.Loopback`), never `+` / `*` / `0.0.0.0`. No URL ACL, no admin. Enforced by `Assert-LoopbackPrefix` in [templates/ports/LoopbackPort.ps1](templates/ports/LoopbackPort.ps1) before `Prefixes.Add` (only `localhost`, `127.0.0.1`, `[::1]`; elevated `+`/`*` prefixes would otherwise really listen on all interfaces).
2. **Preferred port:** `-Port <n>`, else the port remembered in `settings.json`, else the start of the tool's block above. An explicit `-Port` is used **exactly** (no walking; a busy port that is not the same tool is a clear error), unless the tool also takes its own scan-size parameter (for example Lasso's `-PortScanCount`). A remembered port moves the start, and the block size stays the same.
3. **Walk the block:** a port is free only if it is free on **both** IPv4 and IPv6 loopback and the HttpListener starts. If it is busy, probe `/__fleethacker/id` and apply the policy (above), otherwise try the next port in the tool's **own block**. Never scan into another tool's block, never bind port 0, never pick a random port (except Data Noodler's opt-in site mode, 30000-46999). If the block is full, stop with a clear error naming the tool and the block, in the log and in a message box.
4. **No race:** keep the listener that started. Don't probe a port, close it and rebind.
5. **Report:** log the port you actually got and open or print `http://localhost:<port>/`.
6. **Own instance only:** stop a previous instance only through the policy above (shutdown endpoint, then a pid + path check). A `.pid` file plus a command-line check is still fine for tools that cannot serve the id endpoint yet. Never stop another program.
- **Verifying the bind:** a valid http.sys `localhost` listener shows in `netstat` as `0.0.0.0:<port>` / `[::]:<port>` owned by PID 4 (System), so netstat can't prove a loopback-only bind. Check with `netsh http show servicestate` (registered URLs should be `http://localhost:<port>/`) and by sending a request from a non-loopback address, which must fail.
7. **Validate (keystone pattern):** the caller passes `IPAddress.IsLoopback`, `Host` is `localhost:<port>`, and `Origin` matches.
8. **Test:** [templates/tests/LoopbackPort.Tests.ps1](templates/tests/LoopbackPort.Tests.ps1).

### Notes
- The overlaps this resolves: Phoenix LAI's old 8765-8789 scan, Lasso's 100-port scan, Synapse's served edition on 8765 (the same port as Lasso), MailHawk's 8766 (inside Lasso's new block), TalkForge's scan up to 65535, and the OS-ephemeral fallbacks.
- **Never downgrade:** under reuse, restart and exclusive, a running copy that reports a **newer** version is reused (open the browser to it and exit), and the launcher logs that a stale launcher was used. An older copy is still replaced (or refused, for exclusive) as the table says.
- **Exception, multi:** tools built for parallelism always start another copy on the next free port in their block, whatever version is running. They never reuse and never stop anything.
- Versions compare as dotted numbers (`v1.10.0` > `1.9.2`; a `-suffix` is ignored). A version that does not parse counts as older, so policy applies.
- data-noodler, phoenix-lai and keystone bind `localhost`, which meets the rule.
