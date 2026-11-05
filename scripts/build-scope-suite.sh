#!/usr/bin/env bash
# Build SCOPE_suite.zip from every repository in the org whose VISIBILITY.md
# first line is exactly "public". Each repository is a top-level folder from a
# fresh shallow checkout of its default branch.
#
# Public repositories are listed with the Actions GITHUB_TOKEN when it is set,
# and with an anonymous API read otherwise. No extra secret is required.
# This script does not upload a release; .github/workflows/scope-suite.yml does that.
#
# Usage:
#   scripts/build-scope-suite.sh [--org NAME] [--out DIR]
#   scripts/build-scope-suite.sh --list-only
#   scripts/build-scope-suite.sh --pack-dir DIR --out DIR
#   scripts/build-scope-suite.sh --render-notes --sha256 HEX --manifest FILE < body.md

set -euo pipefail

DEFAULT_ORG="fleethacker-data-crucible"
# GitHub documents a 2 GB limit on release assets. Stay under the decimal 2 GB
# so a bundle that would be rejected is failed here, with the largest files logged.
DEFAULT_MAX_BYTES=2000000000

ORG="$DEFAULT_ORG"
OUT_DIR="dist"
WORK_DIR=""
PACK_DIR=""
LIST_ONLY=0
KEEP_WORK=0
MAX_BYTES="$DEFAULT_MAX_BYTES"
RENDER_NOTES=0
SHA256_ARG=""
MANIFEST_ARG=""
CLEAN_WORK=""
# gh uses GITHUB_TOKEN in Actions. curl is the anonymous fallback.
API_MODE=""

usage() {
  cat <<'EOF'
Usage: scripts/build-scope-suite.sh [options]

Build SCOPE_suite.zip from org repositories whose VISIBILITY.md first line is public.

Options:
  --org NAME         GitHub organization (default: fleethacker-data-crucible)
  --out DIR          Output directory (default: dist)
  --work DIR         Scratch directory, removed on exit (default: a new temp directory)
  --pack-dir DIR     Zip repositories already checked out as child folders.
                     Does not contact GitHub.
  --list-only        Print the public repositories and exit without cloning
  --keep-work        Leave the scratch directory in place
  --max-bytes N      Fail when the zip is this size or larger (default: 2000000000)
  --render-notes     Rewrite release notes on stdin. Requires --sha256.
                     --manifest supplies the repository list.
  --sha256 HEX       Digest used by --render-notes
  --manifest FILE    SCOPE-MANIFEST.txt used by --render-notes
  -h, --help         Show this help
EOF
}

die() {
  local msg="$*"
  printf 'error: %s\n' "$msg" >&2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::error::%s\n' "$(printf '%s' "$msg" | tr '\n' ' ')"
  fi
  exit 1
}

log() {
  printf '%s\n' "$*" >&2
}

abspath() {
  local path=$1 resolved
  if resolved=$(realpath -m -- "$path" 2>/dev/null) && [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return
  fi
  python3 -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$path"
}

# First line of VISIBILITY.md: drop a UTF-8 BOM, CR, and surrounding whitespace.
# Comparison stays case-sensitive. "public-candidate" is not "public".
normalize_visibility_line() {
  local line=$1
  line=${line%$'\r'}
  line=${line#$'\xef\xbb\xbf'}
  line=${line#"${line%%[![:space:]]*}"}
  line=${line%"${line##*[![:space:]]}"}
  printf '%s' "$line"
}

# stdout: include, skip, or refuse
# refuse means VISIBILITY.md says public but the GitHub repo is private.
decide_repo() {
  local marker=$1 github_visibility=$2
  local norm
  norm=$(normalize_visibility_line "$marker")
  if [ "$norm" != "public" ]; then
    printf 'skip\n'
    return
  fi
  if [ "$github_visibility" = "private" ]; then
    printf 'refuse\n'
    return
  fi
  printf 'include\n'
}

assert_repo_name() {
  local name=$1
  if [ "$name" = "SCOPE-MANIFEST.txt" ]; then
    die "Refusing repository name SCOPE-MANIFEST.txt because that file is the suite manifest."
  fi
  if ! printf '%s' "$name" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    die "Refusing repository name '${name}'. Expected letters, numbers, dots, underscores, or hyphens."
  fi
}

assert_branch_name() {
  local branch=$1
  if ! printf '%s' "$branch" | grep -Eq '^[A-Za-z0-9._/-]+$'; then
    die "Refusing branch name '${branch}'."
  fi
  case "$branch" in
    *..*|-*|/*|*/) die "Refusing branch name '${branch}'." ;;
  esac
}

require_cmd() {
  local cmd=$1
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
}

# Actions provides GITHUB_TOKEN. gh reads GH_TOKEN first, so copy the default
# token across when that is the one that is set. Never prompt for another secret.
prefer_default_token() {
  if [ -z "${GH_TOKEN:-}" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
    export GH_TOKEN="$GITHUB_TOKEN"
  fi
  export GIT_TERMINAL_PROMPT=0
  export GH_PROMPT_DISABLED=1
}

auth_failure() {
  local err_file=$1
  grep -Eq 'HTTP 401|HTTP 403|Bad credentials|authentication required|gh auth login|to authenticate' "$err_file"
}

ensure_api_mode() {
  if [ -n "$API_MODE" ]; then
    return
  fi
  if command -v gh >/dev/null 2>&1; then
    API_MODE=gh
  elif command -v curl >/dev/null 2>&1; then
    API_MODE=curl
    log "gh is not installed. Reading public repositories anonymously."
  else
    die "gh or curl is required to list public repositories."
  fi
}

use_anonymous_api() {
  command -v curl >/dev/null 2>&1 || die "Could not authenticate to GitHub, and curl is not available for an anonymous public read."
  if [ "$API_MODE" != "curl" ]; then
    log "No usable token. Reading public repositories anonymously."
    API_MODE=curl
  fi
}

curl_headers() {
  local accept=${1:-application/vnd.github+json}
  CURL_HEADERS=(-H "Accept: ${accept}" -H "User-Agent: edge-ops-scope-suite")
  if [ -n "${GH_TOKEN:-}" ]; then
    CURL_HEADERS+=(-H "Authorization: Bearer ${GH_TOKEN}")
  fi
}

render_notes() {
  local sha=$1
  local manifest=$2
  if ! printf '%s' "$sha" | grep -Eq '^[0-9a-fA-F]{64}$'; then
    die "SHA256 must be 64 hex characters."
  fi
  sha=$(printf '%s' "$sha" | tr '[:upper:]' '[:lower:]')

  local body
  body=$(cat | tr -d '\r')
  body=$(printf '%s\n' "$body" | awk '
    /<!-- scope-suite -->/ { skip = 1; next }
    /<!-- \/scope-suite -->/ { skip = 0; next }
    skip { next }
    { print }
  ')
  # shellcheck disable=SC2016 # backticks are literal sed syntax, not command substitution
  body=$(printf '%s\n' "$body" | sed -E 's|SHA256: `?[0-9a-fA-F]{64}`?|SHA256: `'"$sha"'`|g')
  body=$(printf '%s\n' "$body" | awk '
    { lines[NR] = $0 }
    END {
      n = NR
      while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ')

  local count=0
  local names=""
  local noun=""
  local name=""
  if [ -n "$manifest" ]; then
    [ -f "$manifest" ] || die "Manifest not found: ${manifest}"
    while IFS=$'\t' read -r name _rest || [ -n "$name" ]; do
      name=${name%$'\r'}
      case "$name" in
        ''|\#*) continue ;;
      esac
      assert_repo_name "$name"
      names="${names}- ${name}"$'\n'
      count=$((count + 1))
    done < "$manifest"
  fi

  local block
  if [ "$count" -eq 1 ]; then
    noun="repository"
  else
    noun="repositories"
  fi
  block=$(cat <<EOF
<!-- scope-suite -->
### SCOPE suite bundle

\`SCOPE_suite.zip\` is every repository in \`${ORG}\` whose \`VISIBILITY.md\` first line is \`public\` (${count} ${noun}). Each repository is a top-level folder from a shallow checkout of its default branch. \`.git\`, \`*.mp4\`, \`_site\` build output, and any previous \`SCOPE_suite.zip\` are left out.

Repositories:

${names}
SHA256: \`${sha}\`

The same digest is attached as \`SCOPE_suite.zip.sha256\`.
<!-- /scope-suite -->
EOF
)

  if [ -n "$body" ]; then
    printf '%s\n\n%s\n' "$body" "$block"
  else
    printf '%s\n' "$block"
  fi
}

cleanup() {
  if [ -n "$CLEAN_WORK" ] && [ "$KEEP_WORK" -eq 0 ]; then
    rm -rf "$CLEAN_WORK"
  fi
}

reject_overlapping_out() {
  local out_abs=$1
  local stage_abs=$2
  local pack_abs=${3:-}
  if [ "$out_abs" = "$stage_abs" ] || [[ "$out_abs" == "$stage_abs"/* ]]; then
    die "Refusing to write the bundle inside the checkout directory (${stage_abs}). Choose an --out path outside it so SCOPE_suite.zip is not packed into itself."
  fi
  if [ -n "$pack_abs" ]; then
    if [ "$out_abs" = "$pack_abs" ] || [[ "$out_abs" == "$pack_abs"/* ]]; then
      die "Refusing to write the bundle inside --pack-dir (${pack_abs}). Choose an --out path outside it so a previous SCOPE_suite.zip is not packed into the next one."
    fi
  fi
}

append_repo_tsv() {
  local json_file=$1
  local dest=$2
  python3 - "$json_file" "$dest" <<'PY'
import json, sys
src, dest = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as handle:
    data = json.load(handle)
with open(dest, "a", encoding="utf-8") as out:
    for repo in data:
        visibility = "private" if repo.get("private") else "public"
        archived = "yes" if repo.get("archived") else "no"
        name = repo.get("name") or ""
        branch = repo.get("default_branch") or ""
        out.write(f"{name}\t{branch}\t{visibility}\t{archived}\n")
PY
}

curl_list_public_repos() {
  local dest=$1
  local url="https://api.github.com/orgs/${ORG}/repos?per_page=100&type=public"
  : > "$dest"
  local page headers code next
  while [ -n "$url" ]; do
    page=$(mktemp)
    headers=$(mktemp)
    curl_headers
    code=$(curl -sS -D "$headers" -o "$page" -w "%{http_code}" "${CURL_HEADERS[@]}" "$url" || true)
    if [ "$code" != "200" ]; then
      local detail=""
      detail=$(python3 -c 'import json,sys
try:
    msg = json.load(open(sys.argv[1], encoding="utf-8")).get("message", "")
except Exception:
    msg = ""
print(msg[:200])' "$page" 2>/dev/null || true)
      rm -f "$page" "$headers"
      die "Could not list public repositories in ${ORG} (HTTP ${code}). ${detail} The workflow uses the default GITHUB_TOKEN for this public read."
    fi
    append_repo_tsv "$page" "$dest"
    next=$(grep -i '^link:' "$headers" | tr ',' '\n' | sed -n 's/.*<\([^>]*\)>;[[:space:]]*rel="next".*/\1/p' | head -n 1 || true)
    rm -f "$page" "$headers"
    url=$next
  done
}

curl_visibility_line() {
  local name=$1
  local branch_q=$2
  local body code line
  body=$(mktemp)
  curl_headers "application/vnd.github.raw"
  code=$(curl -sS -o "$body" -w "%{http_code}" "${CURL_HEADERS[@]}" \
    "https://api.github.com/repos/${ORG}/${name}/contents/VISIBILITY.md?ref=${branch_q}" || true)
  if [ "$code" = "404" ]; then
    rm -f "$body"
    return 2
  fi
  if [ "$code" != "200" ]; then
    local detail=""
    detail=$(python3 -c 'import json,sys
try:
    msg = json.load(open(sys.argv[1], encoding="utf-8")).get("message", "")
except Exception:
    msg = ""
print(msg[:200])' "$body" 2>/dev/null || true)
    rm -f "$body"
    die "Could not read ${ORG}/${name}/VISIBILITY.md (HTTP ${code}). ${detail} Public repositories are read with the Actions GITHUB_TOKEN, or anonymously when no token is set."
  fi
  line=""
  IFS= read -r line < "$body" || line=""
  rm -f "$body"
  normalize_visibility_line "$line"
}

fetch_visibility_line() {
  local name=$1
  local branch=$2
  local body err rc line branch_q
  branch_q=${branch//\//%2F}
  ensure_api_mode
  if [ "$API_MODE" = "curl" ]; then
    curl_visibility_line "$name" "$branch_q"
    return
  fi
  body=$(mktemp)
  err=$(mktemp)
  set +e
  gh api -H "Accept: application/vnd.github.raw" \
    "repos/${ORG}/${name}/contents/VISIBILITY.md?ref=${branch_q}" >"$body" 2>"$err"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    if grep -q 'HTTP 404' "$err" || grep -q '"status": "404"' "$body" || grep -q '"status":"404"' "$body"; then
      rm -f "$body" "$err"
      return 2
    fi
    if auth_failure "$err"; then
      rm -f "$body" "$err"
      use_anonymous_api
      curl_visibility_line "$name" "$branch_q"
      return
    fi
    local detail
    detail=$(tr '\n' ' ' < "$err")
    rm -f "$body" "$err"
    die "Could not read ${ORG}/${name}/VISIBILITY.md (${detail})."
  fi
  line=""
  IFS= read -r line < "$body" || line=""
  rm -f "$body" "$err"
  normalize_visibility_line "$line"
}

discover_repos() {
  local dest=$1
  local list err
  list=$(mktemp)
  err=$(mktemp)
  ensure_api_mode
  prefer_default_token
  log "Listing public repositories in ${ORG}."
  if [ "$API_MODE" = "gh" ]; then
    if ! gh api --paginate "orgs/${ORG}/repos?per_page=100&type=public" \
      --jq '.[] | [.name, (.default_branch // ""), (if .private then "private" else "public" end), (if .archived then "yes" else "no" end)] | @tsv' \
      >"$list" 2>"$err"; then
      if auth_failure "$err"; then
        rm -f "$err"
        use_anonymous_api
        curl_list_public_repos "$list"
      else
        local detail
        detail=$(tr '\n' ' ' < "$err")
        rm -f "$list" "$err"
        die "Could not list public repositories in ${ORG} (${detail})."
      fi
    else
      rm -f "$err"
    fi
  else
    rm -f "$err"
    curl_list_public_repos "$list"
  fi
  : > "$dest"
  local included=0 skipped=0
  local name branch visibility archived marker decision
  while IFS=$'\t' read -r name branch visibility archived || [ -n "${name:-}" ]; do
    [ -n "${name:-}" ] || continue
    assert_repo_name "$name"
    if [ -z "$branch" ]; then
      log "skip ${name} reason=no-default-branch"
      skipped=$((skipped + 1))
      continue
    fi
    assert_branch_name "$branch"
    set +e
    marker=$(fetch_visibility_line "$name" "$branch")
    local fetch_rc=$?
    set -e
    if [ "$fetch_rc" -eq 2 ]; then
      log "skip ${name} reason=no-VISIBILITY.md"
      skipped=$((skipped + 1))
      continue
    fi
    if [ "$fetch_rc" -ne 0 ]; then
      die "Failed while reading VISIBILITY.md for ${name}."
    fi
    decision=$(decide_repo "$marker" "$visibility")
    case "$decision" in
      include)
        printf '%s\t%s\t%s\n' "$name" "$branch" "$archived" >> "$dest"
        included=$((included + 1))
        log "include ${name} branch=${branch} archived=${archived}"
        ;;
      refuse)
        die "Repository ${ORG}/${name} is private on GitHub but VISIBILITY.md says public. Refusing to put private source into SCOPE_suite.zip. Make the repository public, or change VISIBILITY.md, then re-run."
        ;;
      skip)
        log "skip ${name} reason=visibility:${marker:-empty}"
        skipped=$((skipped + 1))
        ;;
      *)
        die "Unexpected classification '${decision}' for ${name}."
        ;;
    esac
  done < "$list"
  rm -f "$list"
  log "Discovery finished. included=${included} skipped=${skipped}"
  if [ "$included" -lt 1 ]; then
    die "No repositories in ${ORG} have VISIBILITY.md starting with public. The list is the org's public repositories only."
  fi
}

clone_public_repo() {
  local name=$1
  local branch=$2
  local dest=$3
  # Public clones do not need a credential in .git. Prefer an anonymous checkout,
  # then the default token via gh if that is refused.
  rm -rf "$dest"
  if git -c credential.helper= clone --depth 1 --branch "$branch" --single-branch --no-tags \
    "https://github.com/${ORG}/${name}.git" "$dest"; then
    return 0
  fi
  rm -rf "$dest"
  gh repo clone "https://github.com/${ORG}/${name}.git" "$dest" -- --depth 1 --branch "$branch" --single-branch --no-tags
}

# gh's credential helper can display a token in `git remote -v` via url.insteadOf.
# Rewrite origin to a plain HTTPS URL and refuse to continue if a credential
# was actually written under .git. The directory is removed before the zip.
scrub_clone_credentials() {
  local dest=$1
  local name=$2
  git -C "$dest" remote set-url origin "https://github.com/${ORG}/${name}.git"
  git -C "$dest" remote remove upstream >/dev/null 2>&1 || true
  if grep -R -l -E 'x-access-token:|github_pat_|ghp_|gho_|ghs_' "${dest}/.git" >/dev/null 2>&1; then
    rm -rf "$dest"
    die "Clone of ${ORG}/${name} left a GitHub credential in .git. Refusing to build the suite."
  fi
}

clone_repos() {
  local selected=$1
  local stage=$2
  local bundled=$3
  : > "$bundled"
  local name branch archived dest sha
  while IFS=$'\t' read -r name branch archived || [ -n "$name" ]; do
    [ -n "$name" ] || continue
    dest="${stage}/${name}"
    log "clone ${ORG}/${name} branch=${branch}"
    if ! clone_public_repo "$name" "$branch" "$dest"; then
      die "Failed to clone ${ORG}/${name} (branch ${branch}). Public repositories are cloned with the Actions GITHUB_TOKEN, or anonymously when no token is set."
    fi
    scrub_clone_credentials "$dest" "$name"
    sha=$(git -C "$dest" rev-parse HEAD)
    rm -rf "${dest}/.git"
    printf '%s\t%s\t%s\t%s\n' "$name" "$branch" "$sha" "$archived" >> "$bundled"
    log "cloned ${name} ${sha}"
  done < "$selected"
}

pack_local_repos() {
  local pack=$1
  local stage=$2
  local bundled=$3
  : > "$bundled"
  local dir name sha branch
  local found=0
  shopt -s nullglob
  for dir in "$pack"/*/; do
    name=$(basename "$dir")
    assert_repo_name "$name"
    mkdir -p "${stage}/${name}"
    cp -a "${dir}/." "${stage}/${name}/"
    sha="unknown"
    branch="local"
    if [ -d "${stage}/${name}/.git" ] || [ -f "${stage}/${name}/.git" ]; then
      if git -C "${stage}/${name}" rev-parse HEAD >/dev/null 2>&1; then
        sha=$(git -C "${stage}/${name}" rev-parse HEAD)
        branch=$(git -C "${stage}/${name}" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'local')
      fi
    fi
    printf '%s\t%s\t%s\t%s\n' "$name" "$branch" "$sha" "no" >> "$bundled"
    found=$((found + 1))
  done
  shopt -u nullglob
  if [ "$found" -lt 1 ]; then
    die "No repository folders found in ${pack}."
  fi
}

# Remove VCS metadata, videos, generated site output, and a previous suite zip
# so the archive cannot contain an earlier SCOPE_suite.zip or the hub's _site build.
strip_tree() {
  local root=$1
  find "$root" \( -name .git -o -name _site \) \( -type d -o -type l \) -prune -exec rm -rf {} +
  find "$root" \( -type f -o -type l \) \( -iname '*.mp4' -o -name 'SCOPE_suite.zip' -o -name 'SCOPE_suite.zip.sha256' -o -name 'public.zip' \) -delete
}

write_manifest() {
  local bundled=$1
  local dest=$2
  {
    echo "# SCOPE suite manifest"
    echo "# org: ${ORG}"
    echo "# created: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# checkout: shallow clone of each repository default branch"
    echo "# omitted: .git, *.mp4, _site/, SCOPE_suite.zip, SCOPE_suite.zip.sha256, public.zip"
    printf '# %s\t%s\t%s\t%s\n' "name" "branch" "commit" "archived"
    LC_ALL=C sort -t $'\t' -k1,1 "$bundled"
  } > "$dest"
}

write_sha256() {
  local zip_path=$1
  local dest=$2
  local dir base
  dir=$(dirname "$zip_path")
  base=$(basename "$zip_path")
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$dir" && sha256sum "$base") > "$dest"
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$dir" && shasum -a 256 "$base") > "$dest"
  else
    die "sha256sum or shasum is required to checksum the bundle."
  fi
}

check_zip_size() {
  local zip_path=$1
  local stage=$2
  local size
  size=$(wc -c < "$zip_path" | tr -d '[:space:]')
  log "SCOPE_suite.zip is ${size} bytes (limit ${MAX_BYTES})."
  if [ "$size" -ge "$MAX_BYTES" ]; then
    log "Largest files in the staged tree:"
    find "$stage" -type f -exec wc -c {} + | LC_ALL=C sort -nr | head -n 20 >&2 || true
    die "SCOPE_suite.zip is ${size} bytes, which meets or exceeds the ${MAX_BYTES}-byte limit (GitHub's 2 GB release asset limit). The bundle was not left as a release asset. Remove large files from the public repositories or narrow what the script packs."
  fi
}

build_zip() {
  local stage=$1
  local bundled=$2
  local out_abs=$3
  local manifest="${stage}/SCOPE-MANIFEST.txt"
  write_manifest "$bundled" "$manifest"
  local zip_path="${out_abs}/SCOPE_suite.zip"
  local sha_path="${out_abs}/SCOPE_suite.zip.sha256"
  rm -f "$zip_path" "$sha_path"
  require_cmd zip
  (
    cd "$stage"
    zip -r -X -y -q "$zip_path" . \
      -x '*.mp4' '*.MP4' \
      -x '*/.git/*' '.git/*' \
      -x '*/SCOPE_suite.zip' 'SCOPE_suite.zip' \
      -x '*/SCOPE_suite.zip.sha256' 'SCOPE_suite.zip.sha256' \
      -x '*/public.zip' 'public.zip' \
      -x '*/_site/*' '_site/*'
  )
  [ -s "$zip_path" ] || die "SCOPE_suite.zip was not created."
  cp "$manifest" "${out_abs}/SCOPE-MANIFEST.txt"
  check_zip_size "$zip_path" "$stage"
  write_sha256 "$zip_path" "$sha_path"
  local sha
  sha=$(awk 'NR==1 { print $1; exit }' "$sha_path")
  printf '%s' "$sha" | grep -Eq '^[0-9a-fA-F]{64}$' || die "Checksum file is missing a SHA256."
  log "Wrote ${zip_path}"
  log "Wrote ${sha_path}"
  log "SHA256 ${sha}"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --org)
        [ "$#" -ge 2 ] || die "--org requires a value."
        ORG=$2
        shift 2
        ;;
      --out)
        [ "$#" -ge 2 ] || die "--out requires a value."
        OUT_DIR=$2
        shift 2
        ;;
      --work)
        [ "$#" -ge 2 ] || die "--work requires a value."
        WORK_DIR=$2
        shift 2
        ;;
      --pack-dir)
        [ "$#" -ge 2 ] || die "--pack-dir requires a value."
        PACK_DIR=$2
        shift 2
        ;;
      --list-only)
        LIST_ONLY=1
        shift
        ;;
      --keep-work)
        KEEP_WORK=1
        shift
        ;;
      --max-bytes)
        [ "$#" -ge 2 ] || die "--max-bytes requires a value."
        MAX_BYTES=$2
        shift 2
        ;;
      --render-notes)
        RENDER_NOTES=1
        shift
        ;;
      --sha256)
        [ "$#" -ge 2 ] || die "--sha256 requires a value."
        SHA256_ARG=$2
        shift 2
        ;;
      --manifest)
        [ "$#" -ge 2 ] || die "--manifest requires a value."
        MANIFEST_ARG=$2
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
  if ! printf '%s' "$ORG" | grep -Eq '^[A-Za-z0-9.-]+$'; then
    die "Unsafe organization name: ${ORG}"
  fi
  if ! printf '%s' "$MAX_BYTES" | grep -Eq '^[0-9]+$'; then
    die "--max-bytes must be a positive integer."
  fi
}

main() {
  parse_args "$@"
  if [ "$RENDER_NOTES" -eq 1 ]; then
    [ -n "$SHA256_ARG" ] || die "--render-notes requires --sha256."
    render_notes "$SHA256_ARG" "$MANIFEST_ARG"
    return
  fi

  require_cmd git
  local out_abs stage pack_abs=""
  if [ -n "$WORK_DIR" ]; then
    mkdir -p "$WORK_DIR"
    CLEAN_WORK=$(abspath "$WORK_DIR")
  else
    CLEAN_WORK=$(mktemp -d "${TMPDIR:-/tmp}/scope-suite.XXXXXX")
    WORK_DIR=$CLEAN_WORK
  fi
  trap cleanup EXIT
  stage="${WORK_DIR}/src"
  mkdir -p "$stage" 
  if [ -n "$PACK_DIR" ]; then
    [ -d "$PACK_DIR" ] || die "--pack-dir is not a directory: ${PACK_DIR}"
    pack_abs=$(abspath "$PACK_DIR")
  fi

  if [ "$LIST_ONLY" -eq 1 ]; then
    [ -z "$PACK_DIR" ] || die "--list-only cannot be combined with --pack-dir."
    prefer_default_token
    local selected="${WORK_DIR}/selected.tsv"
    discover_repos "$selected"
    LC_ALL=C sort -t $'\t' -k1,1 "$selected"
    return
  fi

  out_abs=$(abspath "$OUT_DIR")
  local stage_abs
  stage_abs=$(abspath "$stage")
  reject_overlapping_out "$out_abs" "$stage_abs" "$pack_abs"
  mkdir -p "$OUT_DIR"

  local bundled="${WORK_DIR}/bundled.tsv"
  if [ -n "$PACK_DIR" ]; then
    pack_local_repos "$PACK_DIR" "$stage" "$bundled"
  else
    require_cmd zip
    prefer_default_token
    local selected="${WORK_DIR}/selected.tsv"
    discover_repos "$selected"
    LC_ALL=C sort -t $'\t' -k1,1 -o "$selected" "$selected"
    clone_repos "$selected" "$stage" "$bundled"
  fi

  strip_tree "$stage"
  if find "$stage" -name .git -print -quit | grep -q .; then
    die "A .git directory was still present after stripping. Refusing to zip the suite."
  fi
  build_zip "$stage" "$bundled" "$out_abs"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
