# SCOPE suite bundle

`SCOPE_suite.zip` is the public FleetHacker suite as one release asset. It is built from every repository in `fleethacker-data-crucible` whose `VISIBILITY.md` first line is exactly `public`. Each repository is a top-level folder, from a fresh shallow checkout of that repository's default branch. Repositories with no `VISIBILITY.md`, or with `public-candidate` or `internal-only`, are left out. A new public repository is picked up on the next run. The list is not hard-coded.

The workflow is [`.github/workflows/scope-suite.yml`](../.github/workflows/scope-suite.yml). The script is [`scripts/build-scope-suite.sh`](../scripts/build-scope-suite.sh). The script builds the zip. The workflow attaches it to a release.

## When it runs

- **A release is published.** The trigger is `release: published`. That covers a stable release and a pre-release, including a pre-release that was published from a draft. `release_canidate_alpha` is a pre-release, so a `released`-only trigger would skip it. `prereleased` would skip a later stable release, and it does not run when a pre-release is published from a draft. `created` also runs when a release is published without first being a draft, which would build the zip twice.
- **A manual rebuild.** Actions → **SCOPE suite bundle** → **Run workflow**, and set the tag of an existing release. Example: `release_canidate_alpha`. The workflow file has to be on `main` before GitHub offers that button.
- A pull request runs the offline fixture only. It does not read the secret and it does not upload anything.

Publishing the release from the GitHub UI, or with a token other than the workflow's `GITHUB_TOKEN`, starts the job. A release created by `GITHUB_TOKEN` does not start other workflows. Rebuild that tag with **Run workflow**.

The job does not create a release and does not publish a draft. The tag must already have a published release.

## What gets attached

On the release that triggered the run (or the tag you typed):

- `SCOPE_suite.zip`
- `SCOPE_suite.zip.sha256` (the `sha256sum` line for that zip)

A re-run replaces both assets (`gh release upload --clobber`). Clobber removes the previous asset before the new upload finishes, so a failed upload can leave the tag without that file until the next successful run. The release notes keep their existing text. A `<!-- scope-suite -->` section is added or replaced with the repository list and the same SHA256. A SHA256 already written in the notes is updated to the new digest. The release title, draft flag, pre-release flag, and target are left as they were.

`SCOPE-MANIFEST.txt` inside the zip lists each repository, branch, and commit.

## What is left out

- `.git` directories
- `*.mp4` and `*.MP4` (demo videos stay in Commissioning; the suite zip stays lean). A checkout still downloads those videos, then deletes them before zipping, so the runner needs disk for the Commissioning tree.
- `_site/` build output
- a previous `SCOPE_suite.zip`, `SCOPE_suite.zip.sha256`, or `public.zip` if one is in a checkout

The zip is written outside the checkout, so the bundle cannot contain itself. A fresh clone also omits gitignored build output. The script stops if the zip is 2 GB or larger, which is GitHub's release asset limit, and logs the largest staged files.

A repository that says `public` in `VISIBILITY.md` but is private on GitHub fails the build. Private source is not put on the release.

Submodules are not initialized.

## Runner

`ubuntu-latest`. The org's self-hosted runners used in this repo are Windows machines for PowerShell 5.1 (`[self-hosted, windows, powershell51, headless]` and `[self-hosted, Windows, X64]`). This job is bash, matching [templates/workflows/release-zip.yml](../templates/workflows/release-zip.yml).

## Secret: `SUITE_READ_TOKEN`

The workflow `GITHUB_TOKEN` can upload assets to this repository. It cannot read the other repositories in the org. The build step uses a separate secret and does not fall back to `GITHUB_TOKEN`. If `SUITE_READ_TOKEN` is missing, the job stops before it clones anything.

Create the secret once. Do not put the token in the repository.

1. Create a **fine-grained personal access token** (or a GitHub App installation token).
   - Resource owner: `fleethacker-data-crucible`.
   - Repository access: **All repositories**, so a new public repository is included and a private repository marked `public` fails the build instead of being skipped.
   - Permissions: **Contents: Read-only** and **Metadata: Read-only**. Metadata is required to list the org. Contents is required to read `VISIBILITY.md` and to clone.
2. Add an Actions secret named exactly `SUITE_READ_TOKEN`.
   - Organization secret: Settings → Secrets and variables → Actions → New organization secret. Grant it to `edge-ops` (selected repositories is enough).
   - Or a repository secret on `edge-ops`: Settings → Secrets and variables → Actions.
3. Prefer a fine-grained PAT with an expiry you can renew. A GitHub App installation token works in the same secret, but it expires after one hour, so it is a poor fit unless something refreshes it.

The upload step uses `GITHUB_TOKEN` with `contents: write` only. The read token is not used to edit the release.

## Run it locally

The script only builds files. It does not upload.

```bash
export SUITE_READ_TOKEN=...   # or GH_TOKEN, or gh auth login
./scripts/build-scope-suite.sh --out dist
# dist/SCOPE_suite.zip
# dist/SCOPE_suite.zip.sha256
# dist/SCOPE-MANIFEST.txt
./scripts/build-scope-suite.sh --list-only
```

Check the digest:

```bash
sha256sum -c dist/SCOPE_suite.zip.sha256
```

On Windows PowerShell:

```powershell
Get-FileHash .\dist\SCOPE_suite.zip -Algorithm SHA256
```

To attach a zip you built locally, from a checkout with permission to edit the release:

```bash
gh release upload TAG dist/SCOPE_suite.zip dist/SCOPE_suite.zip.sha256 --clobber
```

## How to test after this is on main

1. Confirm the `SUITE_READ_TOKEN` secret exists and is granted to `edge-ops`.
2. Actions → **SCOPE suite bundle** → **Run workflow** → tag `release_canidate_alpha`.
3. The run should replace `SCOPE_suite.zip` on that existing pre-release, add `SCOPE_suite.zip.sha256`, and refresh the SHA256 in the release notes. It should not create a new release, and the pre-release flag should stay on.

The offline fixture runs on pull requests:

```bash
bash scripts/tests/test-build-scope-suite.sh
```
