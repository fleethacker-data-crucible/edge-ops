# Next pass: edge-ops

Findings from a review on 2026-10-24. Work top to bottom; tick items off as you go. Line numbers are as of commit `b4bd71d` and may have shifted.

The repo itself is tidy: `catalog.json` is valid and matches `assets/catalog-data.js` exactly, and `index.html` loads no CDN. Most of the work is keeping the registry and conventions in step with the tool repos.

## 1. Visibility

- [x] **Preview site.** The `edge-ops-draft` preview repo is retired; the live site is https://fleethacker-data-crucible.github.io/edge-ops/ (Pages from `main`).
- [ ] **Packaging:** make sure `release-zip.yml` can't ship dev or personal files (see section 3).

## 2. Port registry (`PORTS.md`, `catalog.json`)

- [ ] **HIGH: Phoenix's ports collide with other tools.** Phoenix is listed as 1234 only (`PORTS.md:7`), but it also takes 8765-8789 (server) and 8790-8799 (client) (phoenix-lai `src/WebServer.cs:302-305`, `ServerHost.cs:56`). That overlaps:
  - SnipHero 8765, MailHawk 8766 and Keystone 8769 (`PORTS.md:9-11`)
  - the 8770-8799 range for new tools (`PORTS.md:16`)

  Re-plan the ranges with Phoenix.
- [ ] **HIGH: Data Noodler's real ports aren't registered.** It's listed as 8079 only (`PORTS.md:8`, `catalog.json:11`), but:
  - the site runs on 47823, or a random port in 10000-65535 (data-noodler `server/server.ps1:47,211-223`)
  - 8079 has no fallback and exits if busy (line 188), contrary to `PORTS.md:3`
  - on start it force-kills any process matching `*server.ps1*` (lines 171-176), contrary to `CONVENTIONS.md:28`
- [ ] **Keystone override:** the one at `PORTS.md:11` (`-NoBrowser 8770`) doesn't use the standard `-Port <n>` switch (`CONVENTIONS.md:24`).
- [ ] **Phoenix `"network": false` (`catalog.json:12`) is wrong.** The client can call any OpenAI provider on the LAN or the internet.

## 3. Workflows and scripts

- [ ] **MEDIUM: the release workflow tool repos are told to call doesn't exist.** `README.md:53,60`, `CONVENTIONS.md:32` and `templates/workflows/release-zip.yml:7` point at `edge-ops/.github/workflows/release-zip.yml@main`, but there is no `.github/` here. Move the template into place, or fix the docs.
- [ ] **MEDIUM: shell injection in `release-zip.yml`.** `${{ inputs.version }}` (line 66) and `${{ inputs.tool-name }}` (line 108) are pasted straight into bash. Pass them through `env:` instead. Line 86 also runs `rm -rf "$stage"/$p` on caller patterns, so `../..` escapes the staging folder; reject such patterns.
- [ ] **MEDIUM: `release-zip.yml` packages too much.** It excludes only `.git`, `.github` and `dist` (line 85). Add defaults for `.claude/`, `logs*`, `*.tar.gz`, `*.package`, `*.lnk`, `config/users.json` and `swagger-*.txt`. For phoenix-lai this would otherwise ship `.claude/`, logs and archives.
- [ ] **MEDIUM: `scripts/Build-Site.ps1:30-31` can delete the repo.** It runs `Remove-Item (Join-Path $Root $OutDir) -Recurse -Force` unchecked, so `-OutDir ''` or `'..'` wipes the repo or its parent. Refuse anything outside `$Root\_site`.
- [ ] **LOW: `assets/catalog-data.js` is generated three different ways.** `README.md:66` uses Python, `CONVENTIONS.md:41` PowerShell and `Build-Site.ps1:38` its own. Keep one. The PowerShell version uses `Set-Content -Encoding UTF8`, which writes a BOM in PS 5.1.
- [ ] **LOW: links aren't scheme-checked.** `assets/app.js:18` and `Build-Site.ps1:72,82` build links without checking the URL scheme. Allow only `https:`.

## 4. Docs vs TechStack

- [ ] **`CONVENTIONS.md:15` contradicts `TechStack`.**
  - It allows "a CDN as a dev fallback"; TechStack says no CDNs.
  - It says vanilla JS; TechStack says React 19/TS or Svelte 5 + Tailwind, built off-workstation.

  Pick one and update the other.
- [ ] **`README.md:35` allows `HttpListener`; TechStack says `TcpListener`.** Keystone's "may need a URL reservation" (`README.md:27`) means `netsh urlacl`, which needs admin.
- [ ] **The launcher rule doesn't match the tools.** It's exactly one `ToolName.bat` (`CONVENTIONS.md:21`, `README.md:44`), but Data Noodler and Phoenix use `.lnk` files. Phoenix's runs `-EncodedCommand` with `Add-Type` into kernel32, which app control often flags. Update the rule or the tools.
- [ ] **No tool repo has a `LICENSE` or `VERSION` file** (`CONVENTIONS.md:6,11`). Phoenix uses `__version.info`.

## 5. Links and cleanup

- [ ] **Tool cards break when opened from disk.** `assets/app.js:12` links them to `tools/<id>.html`, which exists only in `_site/` output, but `README.md:7` says `index.html` works from disk.
- [ ] **Check the org repos exist before go-live.** Catalog links point at `fleethacker-data-crucible/<repo>`, while current work lives in forks; missing org repos would 404. ARC is removed from the catalog until its rewrite is republished.
- [ ] **`.gitignore` is GitHub's C/C++ template.** Only `_site/` (line 56) is relevant; trim the rest.
- [ ] **`README.md:79` says "Merge PR #1"**, which is already merged.
- [ ] **Images won't load on an offline network.** README and `templates/TOOL-README-TEMPLATE.md` pull them from raw.githubusercontent.com and shields.io.

## 6. SCOPE skin (PR 54), tracked placeholders

- [ ] **`SCOPE_EXPANSION` wording.** `assets/brand-scope.js` carries "Ship Continuity Operations Platform Environment" until Anthony confirms the expansion.
- [ ] **Bridge Warden port.** The card says 8774, which `PORTS.md` lists for Eight-Bells; Bridge Warden walks 8774-8776. Give it a block in `PORTS.md` and drop the card's `portNote`.
- [ ] **Hub tests in CI.** `scripts/tests/Hub.Tests.ps1` and `Flows.Tests.ps1` run locally on Windows PowerShell 5.1 and pwsh 7, but `.github/workflows/site-tests.yml` only runs `Build-Site.Tests.ps1`. Add them to that job (needs a token with `workflow` scope).
- [ ] **SCOPE emblem, light variant.** `assets/brand/scope/emblem-light.png` is the daytime rendering from `scope-emblem-transparent.png`; replace it if a Chart room rendering is made.
