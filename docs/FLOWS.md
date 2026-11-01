# Fleet hand-off files

Fleet apps hand work to one another as **plain files on the local machine**. No app calls another app's internals, and nothing here is sent anywhere. This page is the one place that lists every hand-off file, who writes it, who reads it, and where its exact format is defined.

Each format is owned by the app that writes it, in that app's own repo. This page is a map and a short summary, not a second copy of the field tables: **when this page and the owning document disagree, the owning document wins.** Fix this page afterwards.

Status as of 2026-10-31: every owning document below is in an open pull request in its repo. The links are to those pull requests; replace them with file links when the pull requests merge.

| Hand-off | Writer | Reader | File and schema id | Owning document |
|---|---|---|---|---|
| Capture | SnapShackle | Bowerbird (renames from the text), Capstan and Scrimshaw (import) | `SnapShackle-<time>-<id>.png` plus `<same name>.png.meta.json`, `snapshackle.capture/1` | SnapShackle `docs/CAPTURE-FORMAT.md` ([PR 36](https://github.com/fleethacker-data-crucible/SnapShackle/pull/36)) |
| Editing project | Capstan | Capstan (a published schema lets other tools check a file) | `*.capstan` JSON, `version` 1; `*.capstanz` package | Capstan `docs/PROJECT-FILE.md` and `docs/project.schema.json` ([PR 46](https://github.com/fleethacker-data-crucible/Capstan/pull/46)) |
| Cursor data | Capstan (screen recorder) | Capstan (cursor effects) | `media.cursor` inside the project file | same as the project file |
| Usage counts | PacketRat | Semaphore (data source) | `counts.json`, `packetrat.usage-counts/1` | PacketRat `docs/COUNTS-EXPORT.md` ([PR 41](https://github.com/fleethacker-data-crucible/PacketRat/pull/41)) |
| Backlog health | Halyard | Semaphore (data source) | four CSV files, schema version 1 | Halyard `docs/SEMAPHORE-EXPORT.md` ([PR 45](https://github.com/fleethacker-data-crucible/Halyard/pull/45)) |
| Peer card | Shellback | another Shellback user | JSON, format `synapse-peer-card`, version 1 | Shellback `docs/PEER-CARD-CONTRACT.md` ([PR 40](https://github.com/fleethacker-data-crucible/Shellback/pull/40)) |

## Rules every hand-off follows

- **One writer.** Only the app that owns a format writes it. Another app that edits a file must follow the owner's rules for writers (for example: move a SnapShackle capture and its sidecar together, and add no fields to the sidecar). Keep your own data in your own file.
- **Versioned.** Each format carries a version (a `schema` id such as `x.y/1`, or a `version` field). A change that adds an optional field keeps the version; anything that would break an existing reader raises it.
- **Readers are tolerant.** Ignore fields and values you do not know. Read only the versions you know, and fall back (for example to the PNG alone) for the rest.
- **Local and plain.** UTF-8 text without a byte-order mark, or standard PNG. Nothing needs a network, and nothing is uploaded.
- **Treat the files like their source.** A capture sidecar can hold text read off a screen, a peer card names a person, a backlog export names work items. Do not put them where the source would not go.
- **Machine output follows the CLI rules** in [CONVENTIONS.md](../CONVENTIONS.md#cli-and-api-for-agents): `--out <file>` writes UTF-8 without a BOM, and a result carries a versioned `schema`.

## Capture: PNG plus sidecar (SnapShackle)

- **Where:** `%LOCALAPPDATA%\SnapShackle\Captures\`, one folder, no sub-folders. Older names `CutterMk-`, `Lasso-` and `SnipHero-` are still read.
- **A capture is two files that belong together:** the PNG and a sidecar named exactly `<full PNG name>.meta.json`. The sidecar is optional; a missing one reads as no tags, no note and no text.
- **PNG:** lossless, at the screen's physical pixels. Not edited in place. Do not rely on metadata inside the PNG.
- **Sidecar fields (`snapshackle.capture/1`):** `schema`, `tags` (up to 20 strings), `note` (up to 2000 characters), `ocr` (text Windows OCR found, up to 20000 characters; empty when OCR was unavailable or has not finished).
- **Writers outside SnapShackle:** rename or move only both files together; keep the `SnapShackle-` prefix if the capture should stay in the library; add no sidecar fields.

## Editing project and cursor data (Capstan)

- **Project:** `.capstan` is JSON text with `version` 1 (any other value is refused). It holds the edit only: tracks, clips, media entries (metadata, not bytes), annotations, zooms, captions, markers, redactions, cursor settings and the in and out marks. A `.capstanz` package adds `manifest.json`, `project.json` and the media, for moving a project to another computer.
- **Schema:** the published JSON Schema (draft 2020-12) is `docs/project.schema.json` in Capstan. It is stricter than the loader, which repairs what it can.
- **Cursor data:** a media entry may carry `cursor`, recorded with a screen recording. Times are seconds into the media, all lists are sorted by `t`, and at least one has an entry.
  - `samples`: `{t, x, y}` where `x` and `y` are fractions (0 to 1) of the recorded frame (up to 120000).
  - `clicks`: `{t, button, down}` with `button` one of `left`, `right`, `middle` (up to 20000).
  - `keys`: `{t, key, down}` with `key` 1 to 24 characters (up to 50000).
- **Change rule:** a breaking change bumps `version` and keeps a migration, so an older file still opens.

## Usage counts (PacketRat)

- **Get it:** `PacketRat-CLI.bat stats export --out counts.json`, or `GET /api/stats/export` on the loopback server.
- **Where the document sits:** `result.usage` in the file (inside the `packetrat.result/1` envelope), or `usage` in the API reply. Check that `schema` is `packetrat.usage-counts/1`.
- **Fields:** `schema`, `estimate` (always `true`), `since`, `exportedAt` (ISO 8601 with offset), and `counts`: whole numbers `triaged`, `drafts`, `reports`, `archived`, `moved`, `categorized`, `markedRead`, `dismissed`. Ignore action names you do not know.
- **It is an estimate of work PacketRat did, not a score for a person.** No minutes, message text, senders or subjects are in it. One export is one row of totals; to chart change over time, keep each export under its `exportedAt` time. PacketRat keeps no history.

## Backlog health (Halyard)

- **Get it:** `POST /api/export/semaphore` writes `output/exports/semaphore/{health,items,features,velocity}.csv`; `GET /api/export/semaphore/{table}` returns one as `text/csv`. Synchronize first: the export reflects the snapshot, not the live backlog.
- **Format:** UTF-8 without a BOM, CRLF line ends, a header row, RFC 4180 quoting. Dates are UTC ISO 8601, booleans `true` or `false`, lists inside a cell joined with `;`, empty means unknown. A text cell that starts with `=`, `+`, `-`, `@` or a tab is prefixed with `'`. Columns are only ever added at the right-hand end within a schema version.
- **Tables:** `health` (one row), `items` (one row per work item), `features` (one row per feature), `velocity` (one row per shown sprint). The column lists are in the owning document.

## Peer card (Shellback)

- **What:** the file an employee exports to share an opt-in capability summary with a teammate. A plain JSON object with `format` `synapse-peer-card` and `version` 1. The format id predates the rename to Shellback; existing cards keep importing.
- **Always required:** `format`, `version`, `id` (8 to 70 letters, digits or `-`), `name`, `consent` (`true`) and `skills`. A card without consent is refused.
- **Importer:** drops unknown skill ids and unknown fields without refusing the card, and never trusts the card's claim about itself: an imported card is labelled unverified.
- **Encryption:** a card may be wrapped in an envelope (`format: synapse-encrypted`, AES-256-GCM with a passphrase). The envelope does not change the card.
- **Version rule:** version 1 changes are additive; a breaking change is `version: 2`, and version 1 cards keep importing.

## Not documented yet

- What Semaphore reads from Eight Bells and from generic JSON exports as data sources (Semaphore PR 39, still open).
- Whether Bowerbird follows the capture rules above (rename the PNG and its sidecar together) when it renames a screenshot. Its own document should say so.

## Adding a hand-off

1. Define the format in the writer's repo, with a version, a field list and a test that fails when the real output drifts from the document (SnapShackle's `tests/capture_format_test.ps1` and PacketRat's `tests/Test-PacketRatUsage.ps1` are the pattern).
2. Add one row to the table above and, if the format needs more than a line, a short section. Link the owning document and do not copy its tables.
3. If it is a model, voice or credential flow rather than a file, it belongs in [CONVENTIONS.md](../CONVENTIONS.md) instead (see *Voice*).
