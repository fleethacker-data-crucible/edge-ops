# Fleet snapshot manifest and verifier

Offline pieces of the fleet loader proposed in [edge-ops issue 34](https://github.com/fleethacker-data-crucible/edge-ops/issues/34): a manifest that pins one tested set of packaged Release assets (the **stable** channel), and a script that checks a folder of downloaded assets against it and **fails closed**. Nothing here downloads, unpacks or runs anything, and nothing uses the network.

| File | What it is |
|---|---|
| [fleet-snapshot.schema.json](fleet-snapshot.schema.json) | The manifest format, JSON Schema draft 2020-12. The verifier reads its patterns and limits from this file, so the two cannot drift. |
| [fleet-snapshot.example.json](fleet-snapshot.example.json) | An illustration with placeholder tags and hashes. Verifying it against real assets fails, on purpose. |
| [FleetSnapshot.psm1](FleetSnapshot.psm1) | `Read-FleetSnapshotManifest`, `Test-FleetSnapshot`, `Get-FleetFileSha256`. |
| [Verify-FleetSnapshot.ps1](Verify-FleetSnapshot.ps1) | The command-line check. Exit 0 only when everything matches. |
| [tests/FleetSnapshot.Tests.ps1](tests/FleetSnapshot.Tests.ps1) | Pester 5 tests with local fake assets. |

Windows PowerShell 5.1 and PowerShell 7. ASCII only, no admin, no installs.

## The manifest

```json
{
  "schema": "edge-ops.fleet-snapshot/1",
  "snapshot": "2026.11.0",
  "channel": "stable",
  "created": "2026-11-01T00:00:00Z",
  "tools": [
    {
      "id": "snapshackle",
      "repo": "fleethacker-data-crucible/SnapShackle",
      "tag": "v0.4.0",
      "asset": "SnapShackle-v0.4.0.zip",
      "sha256": "<64 hex digits>",
      "bytes": 123456
    }
  ]
}
```

- One entry per utility, one zip per entry: `repo`, `tag`, `asset` (the Release asset's file name, `ToolName-vX.Y.Z.zip` as in [CONVENTIONS.md](../../CONVENTIONS.md#releases)) and `sha256`. `bytes` is optional; when present it must match.
- `id` is the tool's id in [catalog.json](../../catalog.json). `id`, `repo` and `asset` are unique in a manifest.
- Only the stable (pinned) channel has a manifest. The per-utility latest (beta) channel is checked against the Release's own published checksum and is not described here.
- Unknown fields are refused. A field added later raises the number in `schema`, so an older verifier never half-reads a newer manifest.

## Verifying

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\fleet-loader\Verify-FleetSnapshot.ps1 `
    -Manifest .\snapshot.json -AssetDir D:\fleet\assets -Catalog .\catalog.json
```

`-Catalog` is optional; when given, every manifest tool must exist in the catalog with the same repo. `-Json` prints one `edge-ops.fleet-verify/1` object instead of text. Exit code 0 means every asset matched; **1 means do not unpack or run anything from this set.**

It fails closed. Each of these makes the whole result not OK, and nothing is ever "partly verified":

- the manifest is missing, is not JSON, is not an object, has an unknown schema version or channel, an unknown or missing or null field, an empty tool list, a repeated `id`, `repo` or `asset`, or a malformed value (a bad hash, an asset name with a folder part, a path such as `..\x.zip`, an extension other than `.zip`);
- the asset folder does not exist;
- a pinned asset is missing, is a folder or a link instead of a file, has the wrong size (when the manifest gives one), or has a SHA256 that differs;
- anything unexpected goes wrong while checking.

Files in the folder that the manifest does not list are ignored: they are never used. Hashes compare without regard to case.

## Defaults chosen for the open questions in issue 34

These are proposals for the team to confirm; changing one is a small edit.

- **Where the manifest lives:** committed in edge-ops (suggested path `fleet/snapshot.json`, reviewed as a pull request), and attached to the matching fleet Release as well. No real snapshot is committed yet: a snapshot is a tested set, and none has been cut.
- **Who cuts it:** whoever cuts a fleet Release writes the manifest from the tested assets (a generator is not built yet) and runs this verifier on the assets before publishing.
- **Version number:** `snapshot` is a free name such as `2026.11.0`; nothing parses it.

## Installing (local files only)

[FleetInstall.psm1](FleetInstall.psm1) unpacks a snapshot that [Test-FleetSnapshot](FleetSnapshot.psm1) has already accepted, into `-Root` (default `%LOCALAPPDATA%\FleetHacker\apps`). A failed check unpacks nothing.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\fleet-loader\Install-FleetSnapshot.ps1 `
    -Manifest .\snapshot.json -AssetDir D:\fleet\assets -Catalog .\catalog.json
```

- **Stable.** `Install-FleetSnapshot` records each tool's channel as `stable` in `install-state.json` next to the tools (schema `edge-ops.fleet-install/1`).
- **Beta.** `Install-FleetToolBeta` unpacks one zip only after it matches the published checksum the caller passes. It does not contact GitHub. The record's channel is `beta`.
- **Switch back.** `Switch-FleetToolToStable` reinstalls that tool from the pinned asset and sets the channel back to `stable`.
- **Air-gapped bundle.** `Install-FleetBundle` takes one local zip that contains `snapshot.json` and `assets\`, and unpacks it only after the caller-supplied SHA256 matches.
- **Launch.** `Start-FleetTool -DryRun` resolves one `.ps1` or `.bat` under that tool's folder and names `System32\WindowsPowerShell\v1.0\powershell.exe` or `System32\cmd.exe`. It does not start an `.exe` from the zip. Without `-DryRun` it starts that System32 program. On a machine without Windows PowerShell it returns `E_UNSUPPORTED` and starts nothing.
- **Unpack rules.** Entry names that are absolute, contain `..`, or a drive letter are refused. The written path has to stay under the destination. A link is refused. The expanded size is capped (default 2 GiB) and so is the entry count (default 10000).

## Not built (still to do for issue 34)

Downloading from GitHub, the hub UI, and a token for private repos. Those need a decision: where a snapshot is published, which utilities the first snapshot pins, who cuts it, and where a private-repo token would live (not in the browser, and not in this module). No token is read or stored here.

## Tests

`tests/FleetSnapshot.Tests.ps1` builds fake zips and manifests in a temp folder and checks that a matching set passes and that one changed byte, a missing asset, a wrong size, a folder in place of a file, a bad or null field, a traversal path, a repeated id, an unknown schema or channel and a catalog mismatch each fail. It runs the script itself to check the exit codes.
