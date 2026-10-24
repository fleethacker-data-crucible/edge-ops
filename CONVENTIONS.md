# Suite conventions

These apply to every tool repository in `fleethacker-data-crucible` that is listed in `catalog.json`.

## Repository
- **License:** MIT (`LICENSE` at the root).
- **Description:** one sentence, filled in.
- **Topics:** `fleethacker-suite`, `powershell-5-1`, `no-admin`, `offline`, `app-whitelist-friendly`, plus one of `browser-only`, `browser-ui`, `data-ai`, `security`.
- **Main copy:** the org copy is canonical. Links point to `github.com/fleethacker-data-crucible/<repo>`.
- **README:** follows [templates/TOOL-README-TEMPLATE.md](templates/TOOL-README-TEMPLATE.md).
- **VERSION** file at the root with a single semver line (`1.2.3`), plus a `CHANGELOG.md`.

## Runtime compatibility
- Windows PowerShell **5.1** syntax and .NET Framework 4.x only. No `?.`, `??`, ternaries, `ForEach-Object -Parallel`, or PS7-only cmdlets. Lint with `PSScriptAnalyzer` (`PSUseCompatibleSyntax` targeting 5.1).
- UI: HTML/CSS/vanilla JS that runs in current Edge/Chrome. All assets are local; a CDN may only be a dev fallback.
- Browser-only tools should work from `file://` where possible. Embed data as JS when `fetch` is blocked.
- **Do not** require admin, installers, registry writes outside HKCU, services, scheduled tasks, or a third-party EXE/DLL.
- Flag runtime C# compilation (`Add-Type`/csc) in the catalog. Some app-control policies block it.

## Launchers
- Exactly **one** user-facing `ToolName.bat` that runs:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Start-ToolName.ps1" %*`
- Use `.vbs` only to hide a console window or when `.bat` is blocked. Keep it a thin wrapper around the same `.ps1`.
- Common switches: `-Port <n>`, `-NoBrowser`, `-Demo` (where it applies).

## Local servers
- Bind to **loopback only** (`127.0.0.1`). Never `+` or `*`.
- Use the default port from [PORTS.md](PORTS.md). If it is busy, select a free loopback port and print or open the URL you actually got. Never stop or take over another process.
- Ctrl+C or closing the console stops the server cleanly.

## Releases
- Tag `vX.Y.Z` → the reusable workflow `edge-ops/.github/workflows/release-zip.yml` builds:
  - `ToolName-vX.Y.Z.zip`: a single top-level folder `ToolName-vX.Y.Z/` containing the tool and `VERSION`
  - `ToolName-vX.Y.Z.zip.sha256`
- Big binaries (models, packages) go in release assets, **never** in git history.
- The hub links to `releases/latest`.

## Regenerate the catalog fallback (PowerShell 5.1)
```powershell
$json = Get-Content .\catalog.json -Raw
Set-Content .\assets\catalog-data.js ("window.EDGE_OPS_CATALOG = " + $json + ";") -Encoding UTF8
```
