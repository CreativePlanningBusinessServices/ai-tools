#!/usr/bin/env bash
# Fails if any tracked or untracked file contains a pattern that must not leave CP's own
# systems (account ids, people, client names, CP-account record ids). The patterns live
# OUTSIDE this repo, because the list itself names those things.
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
patterns_file="${SCRUB_PATTERNS_FILE:-$HOME/.config/ai-tools/scrub-patterns.txt}"
email_pattern='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

if [ ! -f "$patterns_file" ]; then
  echo "scrub-check: patterns file not found: $patterns_file" >&2
  echo "scrub-check: ask a maintainer for it; the check can't run without it" >&2
  exit 2
fi

pattern_list="$(mktemp)"
trap 'rm -f "$pattern_list"' EXIT
grep -vE '^[[:space:]]*(#|$)' "$patterns_file" > "$pattern_list" || true
echo "$email_pattern" >> "$pattern_list"

cd "$repo_dir"
files=()
while IFS= read -r -d '' file; do
  [ -f "$file" ] && files+=("$file")
done < <(git ls-files -z --cached --others --exclude-standard)

if [ "${#files[@]}" -eq 0 ]; then
  echo "scrub-check: no files to check"
  exit 0
fi

hits="$(grep -nHIiE -f "$pattern_list" -- "${files[@]}" || true)"
if [ -n "$hits" ]; then
  printf '%s\n' "$hits"
  echo "scrub-check: $(printf '%s\n' "$hits" | wc -l | tr -d ' ') line(s) match blocked patterns — fix before committing" >&2
  exit 1
fi
echo "scrub-check: clean (${#files[@]} files)"
