#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
source "$here/fixtures/fake-sdf-source.sh"
sync="$here/../netsuite/restlets/sync.sh"
js_root=FileCabinet/SuiteScripts/CreativePlanning

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
make_fake_source "$tmp/source"

run_sync() { # <ref> <package dir> [source]
  SYNC_OUT_DIR="$2" bash "$sync" "${3:-$tmp/source}" "$1" > "$tmp/out.log" 2> "$tmp/err.log"
  echo $?
}
worktree_count() { git -C "$tmp/source" worktree list | wc -l | tr -d ' '; }
snapshot() { (cd "$1" && find . -type f -exec shasum {} + | sort); }

mkdir -p "$tmp/pkg"
assert_eq "$(run_sync main "$tmp/pkg")" 0 "good ref exits 0"
for file in RESTlet/cp_saved_search_rl.js RESTlet/cp_file_cabinet_rl.js RESTlet/cp_mr_driver_rl.js \
            netsuite_modules/saved-search-serializer/index.js netsuite_modules/file-cabinet/index.js; do
  if [ -f "$tmp/pkg/$js_root/$file" ]; then pass "copied $file"; else fail "copied $file"; fi
done
for name in saved_search file_cabinet mr_driver; do
  file="Objects/Scripts/RESTlet/customscript_cp_${name}_rl.xml"
  if [ -f "$tmp/pkg/$file" ]; then pass "copied $file"; else fail "copied $file"; fi
done
assert_eq "$(sed -n 1p "$tmp/pkg/SOURCE")" "commit $(git -C "$tmp/source" rev-parse main)" "SOURCE records the commit"
assert_eq "$(sed -n 2p "$tmp/pkg/SOURCE")" "ref main" "SOURCE records the ref"
assert_eq "$(worktree_count)" 1 "temporary worktree removed after success"

echo 'echo DIRTY >> "$out/RESTlet/cp_mr_driver_rl.js"' >> "$tmp/source/build.sh"
before="$(git -C "$tmp/source" status --porcelain)"
mkdir -p "$tmp/pkg-dirty"
assert_eq "$(run_sync main "$tmp/pkg-dirty")" 0 "dirty source checkout still syncs"
assert_not_contains "$(cat "$tmp/pkg-dirty/$js_root/RESTlet/cp_mr_driver_rl.js")" DIRTY "uncommitted source changes are not packaged"
assert_eq "$(git -C "$tmp/source" status --porcelain)" "$before" "source working copy left untouched"
git -C "$tmp/source" checkout -q -- build.sh

mkdir -p "$tmp/pkg-relative"
relative_status="$(cd "$tmp" && SYNC_OUT_DIR="$tmp/pkg-relative" bash "$sync" source main > /dev/null 2>&1; echo $?)"
assert_eq "$relative_status" 0 "relative source path syncs"

for case in "missing-file:did not produce" "bad-dep:loads modules not in the package" \
            "build-fails:build failed" "no-such-ref:ref not found"; do
  ref="${case%%:*}"; message="${case#*:}"
  before="$(snapshot "$tmp/pkg")"
  assert_eq "$(run_sync "$ref" "$tmp/pkg")" 1 "$ref: exits 1"
  assert_contains "$(cat "$tmp/err.log")" "$message" "$ref: says why"
  assert_eq "$(snapshot "$tmp/pkg")" "$before" "$ref: package unchanged"
  assert_eq "$(worktree_count)" 1 "$ref: worktree removed"
done

mkdir -p "$tmp/not-a-repo"
assert_eq "$(run_sync main "$tmp/pkg" "$tmp/not-a-repo")" 1 "non-repo source exits 1"
assert_contains "$(cat "$tmp/err.log")" "not a git repo" "non-repo source says why"

finish
