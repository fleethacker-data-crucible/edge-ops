# Port registry

Default loopback ports and fallback ranges, per the port ruling Jeremy approved on 2026-10-25. Each tool has **one default**. If the default is busy, it falls back only **inside its own listed range** or to an **OS-assigned ephemeral port** (bind to port 0; Windows assigns from 49152-65535).

**Rule: never scan into another tool's port or range.** A fallback scan stays inside the tool's own block. The ephemeral range 49152-65535 is never used as a default.

| Tool | Default | Fallback | Override | Notes |
|---|---|---|---|---|
| Phoenix LAI API (OpenAI-compatible `/v1`) | 1234 (fixed) | none | — | LM Studio-compatible on purpose |
| Data Noodler control panel | 8079 (fixed) | none | settings | |
| Data Noodler site | 47823 (manual mode) | random mode: **30000-46999** | settings `portMode` | random range narrowed from 10000-65535 |
| Lasso (formerly SnipHero Studio) | 8765 | OS-assigned ephemeral | `-Port <n>` / `-PortScanCount <n>` | default `PortScanCount` 1 (was 100, which scanned 8765-8864) |
| MailHawk | 8766 | OS-assigned ephemeral | `MailHawk.bat -Port <n>` | |
| Synapse (served edition) | **8767 (fixed)** | none | `Serve-Synapse.ps1 -Port <n>` | browser data is keyed to the origin, so the port stays fixed; moved from 8765; the standalone HTML file still runs from `file://` with no port |
| Lasso dev instance | 8768 | OS-assigned ephemeral | `dev\Launch-LocalDev.bat` | moved from 8790 |
| Keystone | 8769 | none (clear error); 8770 is the documented manual alternative | `Launch-Keystone.bat -NoBrowser 8770` | |
| New tools | 8771-8779, one each, assigned in order | OS-assigned ephemeral | — | add a row here when you take one |
| Phoenix LAI server UI | **8780** | **8780-8789** | — | was 8765-8789 |
| Phoenix LAI client | 8790 | 8790-8799 | — | 8799 is the dev e2e port |
| TalkForge static server | 25000 | **25000-25099** | `serve-windows.ps1 -Port <n>` | was 25000 up to 65535 |
| Test Chrome debug ports | 9300-9399 (reserved) | — | — | `Start-IsolatedChrome` ([tools/test-harness](tools/test-harness/)); tools must not default here |
| CI-only test ports | 18000-18999 | — | — | e.g. Synapse CI uses 18765 |

## Port handling standard

Reference: phoenix-lai `src\WebServer.cs` (`StartOnFreePort`) and data-noodler `server\server.ps1`. Snippet: [templates/ports/LoopbackPort.ps1](templates/ports/LoopbackPort.ps1).

1. **Listener:** HttpListener on `http://localhost:<port>/` (or TcpListener on `IPAddress.Loopback`), never `+` / `*` / `0.0.0.0`. No URL ACL, no admin. Enforced by `Assert-LoopbackPrefix` in [templates/ports/LoopbackPort.ps1](templates/ports/LoopbackPort.ps1) before `Prefixes.Add` (only `localhost`, `127.0.0.1`, `[::1]`; elevated `+`/`*` prefixes would otherwise really listen on all interfaces).
2. **Preferred port:** `-Port <n>`, else the port remembered in `settings.json`, else the default in the table above. New tools start at **8771**.
3. **Fallback:** a port is free only if it is free on **both** IPv4 and IPv6 loopback. If it is busy, or the bind throws `HttpListenerException`, try the next port in the tool's **own range** from the table (phoenix-lai: server UI 8780-8789, client 8790-8799), or bind an OS-assigned ephemeral port. Never scan into another tool's port. If the range is exhausted, stop with a clear error in the log and a message box. A user-chosen "random" mode is also fine if it draws from 30000-46999 (data-noodler's site).
4. **No race:** keep the listener that started. Don't probe a port, close it and rebind.
5. **Report:** log the port you actually got and open or print `http://localhost:<port>/`.
6. **Own instance only:** a `.pid` file plus a command-line check may stop the tool's own previous instance. Never stop another program.
- **Verifying the bind:** a valid http.sys `localhost` listener shows in `netstat` as `0.0.0.0:<port>` / `[::]:<port>` owned by PID 4 (System), so netstat can't prove a loopback-only bind. Check with `netsh http show servicestate` (registered URLs should be `http://localhost:<port>/`) and by sending a request from a non-loopback address, which must fail.
7. **Validate (keystone pattern):** the caller passes `IPAddress.IsLoopback`, `Host` is `localhost:<port>`, and `Origin` matches.
8. **Test:** [templates/tests/LoopbackPort.Tests.ps1](templates/tests/LoopbackPort.Tests.ps1).

### Notes
- The overlaps this ruling resolves: Phoenix LAI's old 8765-8789 scan, Lasso's 100-port scan, and Synapse's served edition on 8765 (the same port as Lasso).
- data-noodler, phoenix-lai and keystone bind `localhost`, which meets the rule.
