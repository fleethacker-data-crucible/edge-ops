# GHAS alert triage (sprint 2026-11)

Open GitHub Advanced Security alerts from the sprint export. Each row is a disposition after reading the finding and the code. This file does not dismiss alerts on GitHub.

| Alert | Rule / package | Path | Disposition | Reason |
|---|---|---|---|---|
| code-scanning #2 | js/bad-code-sanitization | ui-kit/binnacle/tests/browser-check.mjs | fixed | The click-through check embedded a page-returned point with `JSON.stringify` inside an evaluated function; coordinates are now inserted only as finite JavaScript numeric literals. |

No alert was accepted, so no GitHub dismissal reason is recommended. Nothing needs an owner decision.
