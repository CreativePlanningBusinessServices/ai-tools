#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
repo="$tmp/with space/ai-tools"
mkdir -p "$repo/scripts" "$repo/skills/skill-a" "$repo/skills/skill-b"
echo a > "$repo/skills/skill-a/SKILL.md"; echo b > "$repo/skills/skill-b/SKILL.md"
cp "$here/../scripts/install-skills.sh" "$repo/scripts/install-skills.sh"
target="$tmp/claude skills"

run_install() { CLAUDE_SKILLS_DIR="$target" bash "$repo/scripts/install-skills.sh" > "$tmp/out.log" 2>&1; echo $?; }

assert_eq "$(run_install)" 0 "fresh install exits 0"
assert_eq "$(cat "$target/skill-a/SKILL.md" 2>/dev/null)" a "skill-a link resolves through a path with spaces"
assert_eq "$(readlink "$target/skill-b")" "$repo/skills/skill-b" "skill-b links to the repo copy"

assert_eq "$(run_install)" 0 "re-running exits 0"
assert_contains "$(cat "$tmp/out.log")" "already linked" "re-running reports existing links"

rm "$target/skill-a"; mkdir "$target/skill-a"; echo mine > "$target/skill-a/SKILL.md"
assert_eq "$(run_install)" 1 "an existing non-link exits 1"
assert_contains "$(cat "$tmp/out.log")" "skipped  skill-a" "the conflict is named"
assert_eq "$(cat "$target/skill-a/SKILL.md")" mine "an existing folder is never overwritten"

finish
