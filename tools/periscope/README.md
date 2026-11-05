# Periscope

Local host for the edge-ops catalog. The public GitHub Pages site is the same `index.html`, titled Periscope. This host is what adds Launch.

`Launch-Periscope.bat` at the repo root starts `tools/periscope/Periscope.ps1` with Windows PowerShell 5.1. It binds `http://127.0.0.1/` on port block **8803-8805** (`PORTS.md`, policy `reuse`) and serves `index.html`, `assets/`, `catalog.json`, and `ui-kit/`.

Launch is shown only after `GET /api/periscope/status` succeeds. The public site never shows it. Support tools and tools with no root `.bat` launcher have no Launch button. Halyard Ballast is in that set. Semaphore's catalog entry has `Launch-Semaphore.bat`, so the local host can launch it.

Utilities download only through Gangplank, in a child PowerShell process. The host does not import Gangplank. A token is passed as a DPAPI temp file and deleted in `finally`. If Gangplank is missing, the page shows a walkthrough. A Gangplank release zip is downloaded only when both a public HTTPS URL and a pinned SHA256 are recorded in `Periscope.psm1`. Both are empty, so the walkthrough is the live path.
