# Suite conventions

These apply to every tool repository in `fleethacker-data-crucible` that is listed in `catalog.json`.

## Repository
- **License:** MIT (`LICENSE` at the root).
- **Description:** one sentence, filled in.
- **Topics:** `fleethacker-suite`, `powershell-5-1`, `no-admin`, `offline`, `app-whitelist-friendly`, plus one of `browser-only`, `browser-ui`, `data-ai`, `security`.
- **Main copy:** the org copy is canonical. Links point to `github.com/fleethacker-data-crucible/<repo>`.
- **README:** follows [templates/TOOL-README-TEMPLATE.md](templates/TOOL-README-TEMPLATE.md).
- **Version marker** at the root (`VERSION` semver, or `__version.info`), plus a `CHANGELOG.md`. See *Settings and versioning*.

## Reference repos
The standard is modeled on the two most settled tools, **phoenix-lai** and **data-noodler**. When this file and those repos disagree, the repos win, unless the repo pattern breaks a hard constraint (PS 5.1, no admin, offline, loopback-only bind). Those exceptions are listed in [STANDARDS-EXCEPTIONS.md](STANDARDS-EXCEPTIONS.md).

## Folder layout
```
ToolName\
  ToolName.lnk          user launcher (see Launchers)
  README.md  LICENSE  CHANGELOG.md  version marker (VERSION or __version.info)
  src\ or server\        host scripts (.ps1) and C# sources (.cs); the entry script lives here, not in the root
  html\ or ui\           local HTML/CSS/JS, with third-party JS vendored under ui\js\vendor\ (no CDN)
  config\               shipped defaults (JSON)
  logs\  temp\          created at run time, git-ignored
  tests\                Pester 5 smoke tests (*.Tests.ps1)
  *.bat                 developer/utility only (Package.bat, Unpack.bat, *_Install.bat)
```

## Runtime compatibility
- Windows PowerShell **5.1** and .NET Framework 4.x only. Entry scripts fail fast on anything else:
  `if ($PSVersionTable.PSVersion.Major -ne 5) { throw "Run with Windows PowerShell 5.1 (powershell.exe)..." }` (phoenix-lai `src\run.ps1`).
- UI: HTML/CSS/vanilla JS in current Edge/Chrome. All assets are local. Vendor third-party JS into the repo (data-noodler `ui\js\vendor\billboard\`). No CDN.
- **Do not** require admin, installers, registry writes outside HKCU, services, scheduled tasks, or a third-party EXE/DLL.
- **C# is allowed and preferred for heavy logic**, compiled at run time with `Add-Type` against .NET Framework assemblies only (C# 5). Either compile it in memory (phoenix-lai `src\run.ps1`) or cache the DLL under `<root>\temp\` keyed by a source hash (data-noodler `server\engine-loader.ps1`). Flag `csharpRuntimeCompile` in the catalog; some app-control policies block it.
- Keep temp files inside the tool: `$env:TEMP = $env:TMP = <root>\temp\sys`.

## PowerShell 5.1 rules
Every `.ps1`/`.psm1` must run on stock **Windows PowerShell 5.1** (`powershell.exe`), not just `pwsh`.
- **No PS7-only syntax:** no ternary `a ? b : c`, no `??` / `??=`, no `?.` / `?[]`, no `&&` / `||` pipeline chains, no `ForEach-Object -Parallel`, no `-AsHashtable` on `ConvertFrom-Json`, no `Join-String`, `Get-Error` or other PS7-only cmdlets. (`[Type]::new()` is fine on 5.1.)
- **Encoding: ASCII only** in `.ps1`/`.psm1`/`.psd1`, because PS 5.1 reads BOM-less files as ANSI (data-noodler `engine-loader.ps1`). If a file must contain non-ASCII, save it as UTF-8 **with BOM**. Write output files with an explicit encoding (`[IO.File]::AppendAllText(path, text, [Text.Encoding]::UTF8)`).
- **Errors:** `$ErrorActionPreference = 'Stop'` at the top of every entry script. `Set-StrictMode` is optional; neither reference repo uses it.
- **No admin, installs or CDN** at run time. Dev and CI may install the tools with `-Scope CurrentUser`:
  `Install-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck` and `Install-Module PSScriptAnalyzer -Scope CurrentUser -Force`.
- **Structure:** a thin PowerShell host plus dot-sourced helper scripts (`. (Join-Path $PSScriptRoot 'engine-loader.ps1')`) and C# sources. Modules (`.psm1`) are optional. If PowerShell classes inherit across files, dot-source them in dependency order from one loader. The CI parse step ignores the resulting standalone `TypeNotFound`. List any other files CI should skip in `.ci/lint-exclude.txt`.
- **Lint:** `Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` (copy the file from edge-ops). It enables `PSUseCompatibleSyntax` (5.1), `PSUseCompatibleCommands` (Windows 10/11 desktop 5.1 profile `win-48_x64_10.0.17763.0_5.1.17763.316...`, with `Clear-Host` ignored) and the legacy `PSUseCompatibleCmdlets` (`desktop-5.1.14393.206-windows`). Style rules the reference repos skip by design are excluded (empty catch, ShouldProcess, singular nouns, approved verbs). `PSUseCompatibleTypes` is off because types loaded with `Add-Type` are false positives.

## Launchers
- The user launcher is a **`ToolName.lnk`** in the tool root that runs
  `%SystemRoot%\System32\conhost.exe --headless %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -STA -ExecutionPolicy Bypass ...`
  `conhost --headless` hides the console, so **no VBS is needed** (phoenix-lai `Phoenix_LAI_Server.lnk`, data-noodler `Data Noodler.lnk`).
- The shortcut must work from any extract folder. Use phoenix-lai's `-EncodedCommand` bootstrap, which finds the `.lnk` path and runs `src\<entry>.ps1` beside it. Generate it with [templates/launcher/New-ToolShortcut.ps1](templates/launcher/New-ToolShortcut.ps1). Icons come from `%SystemRoot%` or the tool folder, never a dev-machine path.
- One `.lnk` per program (phoenix-lai ships a server and a client: `Phoenix_LAI_Server.lnk`, `Phoenix_Client.lnk`).
- A `.bat` is for developer and utility tasks only (`Package.bat`, `Unpack.bat`, `*_Install.bat`): a visible console that runs `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0<script>.ps1" %*`, then `pause`. Template: [templates/launcher/ToolName-Dev.bat](templates/launcher/ToolName-Dev.bat). An existing `.bat` launcher may stay as a dev fallback.
- Keep `.bat` files CRLF through `.gitattributes` (`*.bat text eol=crlf`): [templates/gitattributes](templates/gitattributes).
- Common switches: `-Port <n>`, `-NoBrowser`, `-CheckOnly` (self-check, no server).

## Local servers
- **Bind rule:** HttpListener on `http://localhost:<port>/` (or TcpListener on `IPAddress.Loopback`), never `+` / `*` / `0.0.0.0`. `http://localhost:` needs no URL ACL or admin (keystone, data-noodler). **Enforced:** `Start-LoopbackListener` calls `Assert-LoopbackPrefix` before `Prefixes.Add`, which accepts only `localhost`, `127.0.0.1` or `[::1]` and throws on `+`, `*`, `0.0.0.0` or any other host. This matters because, when elevated, `http://+:` and `http://*:` really do listen on every interface.
- **Port blocks:** each tool owns one contiguous block in [PORTS.md](PORTS.md) and walks upward only inside it. Block full means a clear error. No random fallback and no port 0 fallback. Use `Resolve-FleetPort` from [tools/fleet-port/FleetPort.psm1](tools/fleet-port/FleetPort.psm1) (copy it into the tool if the tool can't import from the hub).
- **Self-detection:** serve `GET /__fleethacker/id` (`{tool, version, pid, path}`) and `POST /__fleethacker/shutdown` (`Invoke-FleetIdEndpoint`). Before skipping a busy port, probe it; if it is this tool, apply the tool's one declared policy: `reuse` (default for single-user UI tools), `restart`, `multi` or `exclusive` (tools holding a lease: GPU, Outlook). A **newer** running copy is always reused, never downgraded, and the launcher logs "stale launcher". The exception is `multi`, which always starts another copy on the next free port in its block. See [PORTS.md](PORTS.md#self-detection-and-policies).
- Check every request the way keystone's `Test-KeystoneWebRequest` does: `[Net.IPAddress]::IsLoopback($Request.RemoteEndPoint.Address)`, `Host` is `localhost:<port>` (or `127.0.0.1:<port>`), and `Origin`, when present, is the same origin.
- Free-port checks should test **both** IPv4 (`127.0.0.1`) and IPv6 (`::1`) loopback, because `localhost` can resolve to either (`Test-LoopbackPortFree` in the snippet).
- A tool may stop **its own** previous instance only through its policy: the shutdown endpoint first, then `Stop-Process` on the self-reported pid after checking that process's command line or path (a `.pid` file plus the same check is fine until the tool serves the id endpoint). Never stop or take over another program.
- Closing the window or exiting stops the server and removes the `.pid` file.
- Host skeleton: [templates/host/Start-ToolName.ps1](templates/host/Start-ToolName.ps1).

## Logging
- Logs go in `logs\` inside the tool (`<root>\logs\` or `server\logs\`), one timestamped file per run: `ToolName_yyyy_MM_dd_HHmmss.log` (data-noodler). A machine-readable `.jsonl` next to it is optional (phoenix-lai `ChatLog.cs`).
- Line format: `yyyy-MM-dd HH:mm:ss  [LEVEL] text`.
- The console is hidden, so a fatal start-up error goes to the log **and** a WinForms message box (`Show-Fatal` plus `trap`, data-noodler `server\server.ps1`).
- Logs, `temp\`, `.pid` and `settings.json` holding user state are git-ignored ([templates/gitignore](templates/gitignore)).

## Settings and versioning
- User settings: `settings.json` beside the host script (port, browser, theme). Shipped defaults go in `config\`.
- A version marker in the root (`VERSION` with semver, or a `__version.info` build stamp as in phoenix-lai) plus `CHANGELOG.md`.
- Packaging scripts (`Package.ps1` + `Package.bat`) are fine. Release zips come from the release workflow.

## Tests
- A self-check mode in the entry script (`-CheckOnly`, phoenix-lai `src\run.ps1`): static locality and safety checks with no server.
- Pester 5 smoke tests in `tests\*.Tests.ps1` (start from [templates/tests/](templates/tests/)): every `.ps1` parses on 5.1, the server binds loopback only (fails only on `+`, `*`, `0.0.0.0` or a non-loopback address; `localhost` is fine).
- Browser, desktop, Outlook and GPU tests on the shared VM follow [Test isolation](#test-isolation-shared-windows-test-vm).
- CI: [templates/workflows/ci.yml](templates/workflows/ci.yml) on windows-latest with `shell: powershell` (5.1). It triggers on `main` and `master`. The tests path is `TESTS_PATH`, default `tests`, falling back to `templates/tests`; finding 0 tests is a warning. The token can't write `.github/workflows`, so the file is staged under `templates/`.

## Test isolation (shared Windows test VM)
Source: [tools/test-harness/](tools/test-harness/) (Zombie Admin's harness). Chrome debug ports 9300-9399 are reserved in [PORTS.md](PORTS.md).

Several bots and CI runners share the Windows test VM. These rules keep their browser and UI tests from interfering with each other.

### Setup
- Module: `tools/test-harness/FleetTestHarness.psm1` (Windows PowerShell 5.1+). `Import-Module .\FleetTestHarness.psm1`
- One-time elevated setup: `Install-FleetLockRoot.ps1` creates `C:\ProgramData\fleethacker\locks` and grants Users Modify.
- Override the lock folder with `$env:FLEET_LOCK_ROOT` (the tests do this).

### Browser tests: always use isolated Chrome
```powershell
$c = Start-IsolatedChrome -Agent uikit -RunId $env:GITHUB_RUN_ID -Headless -Url 'file:///D:/x/demo.html'
try { # drive via CDP at http://127.0.0.1:$($c.Port) ($c.DevToolsUrl)
} finally { Stop-IsolatedChrome $c | Out-Null }
```
- Profile: `%LOCALAPPDATA%\fleethacker\chrome\<agent>-<runid>`, always fresh and deleted on stop.
- Debug port: picked at random from **9300-9399**, checked free (Get-NetTCPConnection plus a TcpListener probe), and leased as `port-<n>` while Chrome starts.
- Never use the user's default profile or a fixed debug port. Never `Stop-Process chrome`. Stop only kills processes whose command line contains your profile path.

### Leases for resources that can't be shared
| Resource | Use for |
|---|---|
| `desktop-focus` | anything that needs the interactive desktop or foreground: screenshots, SendKeys/UI Automation, markup tests (lasso), High Contrast or theme toggles |
| `outlook-com` | Outlook COM automation (mailhawk) |
| `gpu` | GPU-heavy work (phoenix-lai) |
| `port-<n>` | a fixed tool port when port fallback is disabled |

```powershell
$l = Enter-FleetLock desktop-focus -Owner "uikit/$env:GITHUB_RUN_ID" -TimeoutSec 600 -Heartbeat
try { ... } finally { Exit-FleetLock $l | Out-Null }
```
- Aliases: `Acquire-FleetLock`, `Renew-FleetLock`, `Release-FleetLock`.
- File `<resource>.json`: owner, pid, host, acquired, heartbeat (ISO 8601 UTC), token.
- Creation is atomic (`FileMode.CreateNew`). Stale means the heartbeat is older than 5 min or the owner PID is dead on this host. Takeover is serialized by a `<resource>.takeover` guard and a rename to a tombstone, so only one taker wins.
- Holding for more than ~4 min: pass `-Heartbeat` (renews every 30 s while the owner PID lives) or call `Update-FleetLock` yourself.
- `Exit-FleetLock` verifies the token and won't release someone else's lock.
- Status: `Get-FleetLocks | Format-Table` (has an IsStale column).
- **Lock-root permissions:** Users:Modify on the lock folder lets *any* local user delete or overwrite other users' lock files. That's acceptable because this is a cooperative lock between our own runners, not a security boundary. Don't rely on it to keep out a hostile process.
- **Test isolation caveat:** the harness's own Pester tests set `FLEET_LOCK_ROOT` to a temp folder but still launch Chrome on the real 9300-9399 ports. Their `port-<n>` leases are invisible to other jobs, so a concurrent job may pick the same port; the free-port probe is the only guard. Avoid running the harness tests alongside other browser jobs on the shared VM.

### Rules
1. Always lease `desktop-focus` for screenshot, SendKeys, focus, or display-setting tests.
2. Always use isolated Chrome for browser tests.
3. Always release and stop in `finally`.
4. Keep leases short; acquire just before the critical section.
5. Don't delete lock files by hand; let stale takeover handle crashed owners.

> **No-admin caveat:** `Install-FleetLockRoot.ps1` is a one-time setup script that writes to `C:\ProgramData` and changes an ACL. It is test-VM infrastructure, not tool runtime. Without elevation, set `$env:FLEET_LOCK_ROOT` to a per-user folder such as `$env:LOCALAPPDATA\fleethacker\locks` (which only coordinates runners under the same Windows account).

## Releases
- Tag `vX.Y.Z` → the reusable workflow `edge-ops/.github/workflows/release-zip.yml` builds:
  - `ToolName-vX.Y.Z.zip`: a single top-level folder `ToolName-vX.Y.Z/` containing the tool and `VERSION`
  - `ToolName-vX.Y.Z.zip.sha256`
- Big binaries (models, packages) go in release assets, **never** in git history.
- The hub links to `releases/latest`.

## Branch pruning
- Template: `templates/workflows/prune-merged-branches.yml`. It's the **one canonical copy**.
- **Adopt it:** copy the file unchanged to `.github/workflows/prune-merged-branches.yml` in the tool repo.
  - Pushing that path needs a token with `workflow` scope (Zombie Admin pushes).
  - After the merge, run it once by hand with `dry_run` left on.
- **Keep every copy identical:** never edit it per repo. Change the template here, then roll the same bytes out to every repo.
- **Runs:**
  - Weekly scheduled runs (Mondays 09:17 UTC) delete for real.
  - Manual runs (`workflow_dispatch`) default to `dry_run: true`, which only logs.
- **Token:** `GITHUB_TOKEN` only, with `contents: write` and `pull-requests: read`. It runs on `ubuntu-latest` (not a PS tool).
- **Never deleted:**
  - the default branch, `main`, `master`, `hub/**`, `preview/**`, `release/**`;
  - protected branches;
  - branches a ruleset blocks from deletion;
  - any branch that is the head (same repo) or **base** of an open PR. Deleting a base closes its PRs.
- **Deleted only if:**
  - a same-repo PR from the branch merged at its current head SHA, or
  - its head is reachable from the default branch. With no PR history, the branch must also not sit at the default tip, and its head must be at least 14 days old.
- **Errors:** each branch fails soft (a 403/422 is logged and the run continues). The job summary lists every decision.

## Regenerate the catalog fallback (PowerShell 5.1)
```powershell
$json = Get-Content .\catalog.json -Raw
Set-Content .\assets\catalog-data.js ("window.EDGE_OPS_CATALOG = " + $json + ";") -Encoding UTF8
```
