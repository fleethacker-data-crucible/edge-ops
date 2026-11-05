#!/usr/bin/env bash
# Offline checks for scripts/build-scope-suite.sh.
# Packs a fixture tree, so it does not need GitHub or a release.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/build-scope-suite.sh"

# shellcheck disable=SC1090,SC1091
source "$SCRIPT"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local got=$1 expected=$2 label=$3
  if [ "$got" != "$expected" ]; then
    fail "${label}: expected [${expected}] got [${got}]"
  fi
}

expect_fail() {
  local needle=$1
  shift
  local out rc
  set +e
  out=$("$@" 2>&1)
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    fail "expected a non-zero exit from: $*"
  fi
  if ! printf '%s\n' "$out" | grep -F -q -- "$needle"; then
    printf '%s\n' "$out" >&2
    fail "output did not contain: ${needle}"
  fi
}

assert_eq "$(normalize_visibility_line 'public')" "public" "plain public"
assert_eq "$(normalize_visibility_line ' public ')" "public" "trimmed public"
assert_eq "$(normalize_visibility_line $'public\r')" "public" "cr public"
assert_eq "$(normalize_visibility_line $'\xef\xbb\xbfpublic')" "public" "bom public"
assert_eq "$(normalize_visibility_line 'public-candidate')" "public-candidate" "candidate stays distinct"
assert_eq "$(normalize_visibility_line 'Public')" "Public" "case is significant"
assert_eq "$(normalize_visibility_line 'internal-only')" "internal-only" "internal"
assert_eq "$(decide_repo 'public' 'public')" "include" "public repo"
assert_eq "$(decide_repo ' public ' 'public')" "include" "trimmed marker"
assert_eq "$(decide_repo 'public' 'private')" "refuse" "private repo marked public"
assert_eq "$(decide_repo 'public-candidate' 'public')" "skip" "candidate is not public"
assert_eq "$(decide_repo 'Public' 'public')" "skip" "wrong case is not public"
assert_eq "$(decide_repo 'internal-only' 'private')" "skip" "internal private repo"
assert_eq "$(decide_repo '' 'public')" "skip" "empty marker"

set +e
( assert_repo_name 'bad name' ) >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "unsafe repository name was accepted"

"$SCRIPT" --help >/dev/null

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PACK="$TMP/pack"
OUT="$TMP/out"
mkdir -p "$PACK/repo-a/.github/workflows" "$PACK/repo-a/dist" "$PACK/repo-a/nested" \
  "$PACK/repo-b/src" "$PACK/repo-b/_site" "$PACK/only-video"

printf 'keep-me\n' > "$PACK/repo-a/README.md"
printf 'ignore\n' > "$PACK/repo-a/.gitignore"
printf 'name: ci\n' > "$PACK/repo-a/.github/workflows/ci.yml"
printf 'built-source\n' > "$PACK/repo-a/dist/keep.txt"
printf 'not-a-video\n' > "$PACK/repo-a/notes.mp4.txt"
printf 'video\n' > "$PACK/repo-a/demo.mp4"
printf 'VIDEO\n' > "$PACK/repo-a/nested/Clip.MP4"
printf 'old-suite\n' > "$PACK/repo-a/SCOPE_suite.zip"
printf 'old-hash\n' > "$PACK/repo-a/SCOPE_suite.zip.sha256"
printf 'public-zip\n' > "$PACK/repo-a/nested/public.zip"
printf 'site\n' > "$PACK/repo-b/_site/index.html"
printf 'app\n' > "$PACK/repo-b/src/app.js"
printf 'mp4-only\n' > "$PACK/only-video/clip.mp4"
ln -s /etc/passwd "$PACK/repo-a/leak"
git -C "$PACK/repo-a" init -q
git -C "$PACK/repo-a" config user.email "suite-test@example.com"
git -C "$PACK/repo-a" config user.name "suite-test"
git -C "$PACK/repo-a" config commit.gpgsign false
git -C "$PACK/repo-a" add README.md
git -C "$PACK/repo-a" commit -q -m "fixture"

# Packing a local tree does not need a token.
env -u GH_TOKEN -u GITHUB_TOKEN GITHUB_ACTIONS=true \
  "$SCRIPT" --pack-dir "$PACK" --out "$OUT" --work "$TMP/work"

[ -s "$OUT/SCOPE_suite.zip" ] || fail "zip was not written"
[ -s "$OUT/SCOPE_suite.zip.sha256" ] || fail "checksum was not written"
[ -s "$OUT/SCOPE-MANIFEST.txt" ] || fail "manifest was not written"
[ -f "$PACK/repo-a/demo.mp4" ] || fail "pack-dir mutated the source tree"
[ -f "$PACK/repo-b/_site/index.html" ] || fail "pack-dir removed source _site"

python3 - "$OUT/SCOPE_suite.zip" "$OUT/SCOPE_suite.zip.sha256" <<'PY'
import hashlib, pathlib, stat, sys, zipfile
zip_path, sha_path = sys.argv[1:]
blob = pathlib.Path(zip_path).read_bytes()
digest = hashlib.sha256(blob).hexdigest()
recorded = pathlib.Path(sha_path).read_text().split()
if recorded[0] != digest:
    raise SystemExit(f"checksum mismatch: {recorded[0]} != {digest}")
if recorded[1] != "SCOPE_suite.zip":
    raise SystemExit(f"checksum filename is {recorded[1]}")
banned = {".git", "_site", "SCOPE_suite.zip", "SCOPE_suite.zip.sha256", "public.zip"}
z = zipfile.ZipFile(zip_path)
names = z.namelist()
required = {
    "repo-a/README.md",
    "repo-a/.gitignore",
    "repo-a/.github/workflows/ci.yml",
    "repo-a/dist/keep.txt",
    "repo-a/notes.mp4.txt",
    "repo-b/src/app.js",
    "SCOPE-MANIFEST.txt",
}
missing = sorted(required - set(names))
if missing:
    raise SystemExit("missing entries: " + ", ".join(missing))
for name in names:
    parts = [part for part in name.split("/") if part]
    for part in parts:
        if part in banned or part.lower().endswith(".mp4"):
            raise SystemExit(f"banned path in zip: {name}")
    info = z.getinfo(name)
    mode = info.external_attr >> 16
    if name == "repo-a/leak":
        if not stat.S_ISLNK(mode):
            raise SystemExit("repo-a/leak was stored as a file instead of a symlink")
        if b"root:" in z.read(name):
            raise SystemExit("symlink target was copied into the zip")
manifest = z.read("SCOPE-MANIFEST.txt").decode()
for repo in ("only-video", "repo-a", "repo-b"):
    if f"\n{repo}\t" not in f"\n{manifest}":
        raise SystemExit(f"manifest missing {repo}")
print(f"zip ok entries={len(names)} sha256={digest}")
PY

grep -q $'^repo-a\t' "$OUT/SCOPE-MANIFEST.txt" || fail "manifest missing repo-a row"
# The committed fixture repo has a real sha; the others are local copies.
grep -E '^repo-a\t' "$OUT/SCOPE-MANIFEST.txt" | grep -q 'unknown' && fail "repo-a sha was not recorded"

expect_fail "inside --pack-dir" \
  "$SCRIPT" --pack-dir "$PACK" --out "$PACK/nested-out" --work "$TMP/work-overlap"
[ ! -d "$PACK/nested-out" ] || fail "overlap check created the output directory inside --pack-dir"

expect_fail "meets or exceeds" \
  "$SCRIPT" --pack-dir "$PACK" --out "$TMP/too-big" --work "$TMP/work-big" --max-bytes 50

if grep -n 'SUITE_READ_TOKEN' "$SCRIPT" "$ROOT/.github/workflows/scope-suite.yml" "$ROOT/docs/scope-suite.md" "$ROOT/README.md"; then
  fail "SUITE_READ_TOKEN is still referenced"
fi

SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
MAN="$TMP/manifest.txt"
cat > "$MAN" <<'EOF'
# SCOPE suite manifest
# name	branch	commit	archived
Bowerbird	main	abc	no
edge-ops	main	def	no
EOF
ORIGINAL="SCOPE suite bundle (built by hand). SHA256: 9daef6d1a06378c110d5297ac4bf2f389998727af4c47e3a1b68ed16ebee49b3"
body1=$(printf '%s\n' "$ORIGINAL" | "$SCRIPT" --render-notes --sha256 "$SHA" --manifest "$MAN")
body2=$(printf '%s\n' "$body1" | "$SCRIPT" --render-notes --sha256 "$SHA" --manifest "$MAN")
[ "$body1" = "$body2" ] || fail "release notes were not stable across a second render"
printf '%s\n' "$body1" | grep -F -q "$SHA" || fail "new digest missing from notes"
if printf '%s\n' "$body1" | grep -F -q "9daef6d1a06378c110d5297ac4bf2f389998727af4c47e3a1b68ed16ebee49b3"; then
  fail "previous digest was left in the notes"
fi
count=$(printf '%s\n' "$body1" | grep -c '<!-- scope-suite -->' || true)
[ "$count" -eq 1 ] || fail "expected one scope-suite marker, found ${count}"
printf '%s\n' "$body1" | grep -F -q -- "- Bowerbird" || fail "notes missing Bowerbird"
printf '%s\n' "$body1" | grep -F -q -- "- edge-ops" || fail "notes missing edge-ops"
printf '%s\n' "$body1" | grep -F -q "2 repositories" || fail "notes missing repository count"

expect_fail "64 hex" \
  "$SCRIPT" --render-notes --sha256 "abcd"

printf 'fixture ok\n'
