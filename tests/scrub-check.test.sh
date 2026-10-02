#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/scripts"
cp "$here/../scripts/scrub-check.sh" "$repo/scripts/scrub-check.sh"
git -C "$repo" init -q
patterns="$tmp/patterns.txt"
printf '# comment lines are ignored\n# blockedclient\nacct-9999999\n' > "$patterns"

run_scrub() { SCRUB_PATTERNS_FILE="$patterns" bash "$repo/scripts/scrub-check.sh" > "$tmp/out.log" 2>&1; echo $?; }

echo 'nothing sensitive here, blockedclient only appears in a comment pattern' > "$repo/clean.md"
assert_eq "$(run_scrub)" 0 "clean files pass"

echo 'see acct-9999999' > "$repo/notes with space.md"
assert_eq "$(run_scrub)" 1 "a blocked pattern fails"
assert_contains "$(cat "$tmp/out.log")" "notes with space.md:1:" "hit names the file (with spaces) and line"
rm "$repo/notes with space.md"

printf 'mail someone@%s\n' example.com > "$repo/mail.md"   # built at runtime so this file passes the scrub
assert_eq "$(run_scrub)" 1 "an email address fails even without a pattern"
rm "$repo/mail.md"

echo 'ACCT-9999999' > "$repo/upper.md"
assert_eq "$(run_scrub)" 1 "patterns are case-insensitive"
rm "$repo/upper.md"

SCRUB_PATTERNS_FILE="$tmp/missing.txt" bash "$repo/scripts/scrub-check.sh" > "$tmp/out.log" 2>&1
assert_eq "$?" 2 "a missing patterns file exits 2"
assert_contains "$(cat "$tmp/out.log")" "patterns file not found" "missing patterns file is explained"

finish
