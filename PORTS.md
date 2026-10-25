# Port registry

Default loopback ports, taken from each tool's README and launch scripts. Every server tool should **fall back to a free port** if its default is busy. Pick new ports from the unused range below and add them here.

| Port | Tool | Override | Source |
|---|---|---|---|
| 1234 | Phoenix LAI server (OpenAI-compatible `/v1`) | see repo docs | phoenix-lai README |
| 8079 | Data Noodler (server control panel) | see repo docs | data-noodler README |
| 8765 | SnipHero Studio | `SnipHero.bat -Port 9000` | sniphero README (auto-selects a free port) |
| 8766 | MailHawk | `MailHawk.bat -Port <n>` | `Start-MailHawk-Web.ps1` (falls back to a free port) |
| 8769 | Keystone | `Launch-Keystone.bat -NoBrowser 8770` | keystone README |
| 25000 | TalkForge static server | next free port automatically | talkforge README |
| — | Synapse | n/a (runs from `file://`) | |
| — | ARC | n/a (CLI/WPF) | |

**Reserved: 9300-9399** for Chrome remote-debugging ports in tests (`Start-IsolatedChrome`, [tools/test-harness](tools/test-harness/)). Tools must not default to this range.

**Suggested range for new tools:** 8770–8799. Keystone documents 8770 as its alternate port, so start new tools at 8771.

## Port handling standard

Reference: phoenix-lai `src\WebServer.cs` (`StartOnFreePort`) and data-noodler `server\server.ps1`. Snippet: [templates/ports/LoopbackPort.ps1](templates/ports/LoopbackPort.ps1).

1. **Listener:** HttpListener on `http://localhost:<port>/` (or TcpListener on `IPAddress.Loopback`), never `+` / `*` / `0.0.0.0`. No URL ACL, no admin.
2. **Preferred port:** `-Port <n>`, else the port remembered in `settings.json`, else the default in the table above. New tools start at **8771**.
3. **Fallback:** a port is free only if it is free on **both** IPv4 and IPv6 loopback. If it is busy, or the bind throws `HttpListenerException`, try the next port in the tool's **own range** (phoenix-lai: server UI 8765-8789, client 8790-8799). If the range is exhausted, stop with a clear error in the log and a message box. A user-chosen "random" mode that picks a free 5-digit port, as data-noodler's site does, is also fine.
4. **No race:** keep the listener that started. Don't probe a port, close it and rebind.
5. **Report:** log the port you actually got and open or print `http://localhost:<port>/`.
6. **Own instance only:** a `.pid` file plus a command-line check may stop the tool's own previous instance. Never stop another program.
7. **Validate (keystone pattern):** the caller passes `IPAddress.IsLoopback`, `Host` is `localhost:<port>`, and `Origin` matches.
8. **Test:** [templates/tests/LoopbackPort.Tests.ps1](templates/tests/LoopbackPort.Tests.ps1).

### Known overlaps and exceptions (not changed here)
- The phoenix-lai web UI scans **8765-8789**, which overlaps SnipHero (8765), MailHawk (8766) and Keystone (8769). Fallback keeps them working side by side, but a real registry entry needs a decision. See [STANDARDS-EXCEPTIONS.md](STANDARDS-EXCEPTIONS.md).
- data-noodler, phoenix-lai and keystone bind `localhost`, which meets the rule.
