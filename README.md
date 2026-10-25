<p align="center"><img src="https://raw.githubusercontent.com/fleethacker-data-crucible/dumping-grounds/main/data_crucible_coin_front.png" alt="FleetHacker Data Crucible" width="120"></p>

# FleetHacker Edge-Ops

Self-contained zip packages for edge automation and analysis. They load and run in user context on nearly any Windows machine, with **no admin rights and no runtime installs**.

This is the **hub** for the `fleethacker-data-crucible` utility suite. Every tool listed here is a separate repository with its own releases. **Browse the catalog:** open [`index.html`](index.html) (it works from GitHub Pages or straight from disk) or read [`catalog.json`](catalog.json).

![PS 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE) ![Chrome engine](https://img.shields.io/badge/browser-Chrome%2FEdge-4285F4) ![No admin](https://img.shields.io/badge/admin-not%20required-3a7d44) ![License MIT](https://img.shields.io/badge/license-MIT-blue)

## Target environment

- Windows with **app-whitelisting** (AppLocker/WDAC-style). Nothing to install.
- **Windows PowerShell 5.1** (built in). No PowerShell 7, Node, Python, or git.exe required.
- A **Chrome-engine browser** (Edge or Chrome) for HTML/JS user interfaces.
- **.bat** files only as a one-click launcher. **.vbs** only when needed, for example to hide a console window.
- Local servers bind to **loopback only** (`127.0.0.1`). See [PORTS.md](PORTS.md).

## Tools

| Tool | Category | What it does | Launch | Default port | Notes |
|---|---|---|---|---|---|
| [Synapse](https://github.com/fleethacker-data-crucible/synapse) | Browser-only | Workforce capability discovery prototype | `Launch-Synapse.bat` (or `dist\Synapse-Standalone.html`) | 8765 | Loopback PS 5.1 server, or single file with no server |
| [TalkForge](https://github.com/fleethacker-data-crucible/talkforge) | Browser-only | In-browser neural text-to-speech (Piper/WASM), offline | `serve.bat` | 25000 | Models ship in releases |
| [SnipHero Studio](https://github.com/fleethacker-data-crucible/sniphero) | PS host + browser UI | Screenshot capture and annotation | `SnipHero.bat` | 8765 | Picks a free port if busy |
| [MailHawk](https://github.com/fleethacker-data-crucible/mailhawk) | PS host + browser UI | Outlook triage into a reviewed action queue | `MailHawk.bat` | 8766 | Needs Outlook |
| [Keystone](https://github.com/fleethacker-data-crucible/keystone) | PS host + browser UI | Git sync workspace without git.exe | `Launch-Keystone.bat` | 8769 | May need a URL reservation |
| [Data Noodler](https://github.com/fleethacker-data-crucible/data-noodler) | Data & AI | Flat-file analytics (CSV/Parquet/Arrow/SQLite) | `Data Noodler.lnk` | 8079 | Compiles C# at run time |
| [Phoenix LAI](https://github.com/fleethacker-data-crucible/phoenix-lai) | Data & AI | Local GPU LLM server (OpenAI API) + chat client | `Phoenix_LAI_Server.lnk` | 1234 | GPU; compiles C# at run time |
| [ARC](https://github.com/fleethacker-data-crucible/powershell-arc) | Security | CAC + TOTP secret vault (CLI/WPF) | `pm.ps1` | — | **External**: source on git.mil |

## Categories

- **Browser-only:** HTML/JS that runs from `file://` or a tiny static server.
- **PowerShell host + browser UI:** a PS 5.1 `HttpListener`/`TcpListener` on loopback serving a local web UI.
- **Data & AI:** heavier tools. Some compile bundled C# through the built-in .NET Framework at run time; some app-control policies block this.
- **Security:** credential and secret tooling.

## Running on a whitelisted Windows machine

1. Download `ToolName-vX.Y.Z.zip` from the tool's **Releases → latest** page and check it against the `.sha256` file:
   `Get-FileHash .\ToolName-vX.Y.Z.zip -Algorithm SHA256`
2. Right-click the zip → Properties → **Unblock**, then extract the **whole** folder.
3. Double-click the single `.bat` launcher. It runs `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File …` for that process only. It never changes machine policy, and it does not override Group Policy or application control.
4. Your browser opens to `http://127.0.0.1:<port>/`. Close the console window (or press Ctrl+C) to stop.

All tools are prototypes or previews unless stated otherwise. Get local authorization and a security review before using them with sensitive data.

## For maintainers

- [CONVENTIONS.md](CONVENTIONS.md): repo, README, launcher, and release rules.
- [templates/TOOL-README-TEMPLATE.md](templates/TOOL-README-TEMPLATE.md): the README layout every tool uses.
- [.github/workflows/release-zip.yml](templates/workflows/release-zip.yml) (staged in `templates/workflows/` until moved by a token with `workflow` scope): reusable release packaging. In a tool repo:

```yaml
on: { push: { tags: ['v*'] } }
permissions: { contents: write }
jobs:
  release:
    uses: fleethacker-data-crucible/edge-ops/.github/workflows/release-zip.yml@main
    with:
      tool-name: SnipHero
```

- To add a tool, edit `catalog.json`, then regenerate the offline fallback:
  `python3 -c "import json;d=json.load(open('catalog.json'));open('assets/catalog-data.js','w').write('window.EDGE_OPS_CATALOG = '+json.dumps(d,indent=2)+';\n')"`
  (or run the PowerShell equivalent in CONVENTIONS.md).

## GitHub Pages site

- Landing page: `index.html` + `assets/`. Each tool also gets its own page, rendered from `templates/pages/tool-page.html` using `catalog.json`. The 404 page comes from `templates/pages/404.html`.
- Build locally (Windows PowerShell 5.1 or pwsh 7):
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Site.ps1` → `_site/` (git-ignored).
- Deploy: `templates/workflows/pages-deploy.yml` (manual `workflow_dispatch` only; `dry_run: true` builds and uploads the artifact without deploying).
- Preview of the look and feel: https://fleethacker-data-crucible.github.io/edge-ops-draft/

## Go-live checklist (Nov 5, 2026, 12:00 PM ET)

1. Merge PR #1 into `main`.
2. Move both workflows into `.github/workflows/` (web UI, or a token with `workflow` scope):
   `templates/workflows/release-zip.yml` → `.github/workflows/release-zip.yml` and
   `templates/workflows/pages-deploy.yml` → `.github/workflows/pages-deploy.yml`.
3. Settings → General → Danger Zone → **Change visibility → Public**.
4. Settings → Pages → **Source = GitHub Actions**.
5. Actions → **pages-deploy** → Run workflow (try `dry_run: true` first if you like, then run it for real).
6. Check https://fleethacker-data-crucible.github.io/edge-ops/ and each `tools/<id>.html` page.
7. Optional: archive or delete the `edge-ops-draft` preview repo.

## License

MIT. See [LICENSE](LICENSE).
