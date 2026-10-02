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
printf '# comment lines are ignored\n# blockedclient\nacct-9999999\ncode-ok:authorname\n' > "$patterns"

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

code_dir="$repo/netsuite/restlets/FileCabinet/SuiteScripts"
mkdir -p "$code_dir"
echo ' * Author: authorname' > "$code_dir/compiled.js"
assert_eq "$(run_scrub)" 0 "a code-ok pattern is allowed in compiled code"

echo 'written by authorname' > "$repo/docs.md"
assert_eq "$(run_scrub)" 1 "a code-ok pattern still fails outside compiled code"
assert_contains "$(cat "$tmp/out.log")" "docs.md:1:" "the non-code hit is named"
rm "$repo/docs.md"

echo '// account acct-9999999' >> "$code_dir/compiled.js"
assert_eq "$(run_scrub)" 1 "other patterns still apply to compiled code"
assert_contains "$(cat "$tmp/out.log")" "compiled.js:2:" "the compiled-code hit is named"
rm -r "$repo/netsuite"

echo 'see acct-9999999' > "$repo/secret.md"
printf '# copied through a Windows clipboard\r\nacct-9999999\r\n' > "$tmp/crlf.txt"
SCRUB_PATTERNS_FILE="$tmp/crlf.txt" bash "$repo/scripts/scrub-check.sh" > "$tmp/out.log" 2>&1
assert_eq "$?" 1 "a CRLF patterns file still blocks"
printf '   acct-9999999   \n' > "$tmp/padded.txt"
SCRUB_PATTERNS_FILE="$tmp/padded.txt" bash "$repo/scripts/scrub-check.sh" > "$tmp/out.log" 2>&1
assert_eq "$?" 1 "surrounding whitespace on a pattern is ignored"
rm "$repo/secret.md"

printf '# only comments\n\ncode-ok:\n   \n' > "$tmp/empty.txt"
SCRUB_PATTERNS_FILE="$tmp/empty.txt" bash "$repo/scripts/scrub-check.sh" > "$tmp/out.log" 2>&1
assert_eq "$?" 2 "a patterns file with no active patterns exits 2"
assert_contains "$(cat "$tmp/out.log")" "no active patterns" "an empty patterns file is explained"

printf 'acct-9999999\ncode-ok:\n' > "$tmp/bare-code-ok.txt"
SCRUB_PATTERNS_FILE="$tmp/bare-code-ok.txt" bash "$repo/scripts/scrub-check.sh" > "$tmp/out.log" 2>&1
assert_eq "$?" 0 "a bare code-ok: line does not match every line"

SCRUB_PATTERNS_FILE="$tmp/missing.txt" bash "$repo/scripts/scrub-check.sh" > "$tmp/out.log" 2>&1
assert_eq "$?" 2 "a missing patterns file exits 2"
assert_contains "$(cat "$tmp/out.log")" "patterns file not found" "missing patterns file is explained"

finish
