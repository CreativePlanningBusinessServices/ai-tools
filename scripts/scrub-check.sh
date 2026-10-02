#!/usr/bin/env bash
# Fails if any tracked or untracked file contains a pattern that must not leave CP's own
# systems (account ids, people, client names, CP-account record ids). The patterns live
# OUTSIDE this repo, because the list itself names those things.
#
# A pattern prefixed `code-ok:` is not applied to the compiled RESTlet code, which ships
# byte-for-byte as built (author headers and dev comments included) so verify.sh can compare
# it with what an account runs. Every other pattern still applies there.
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
patterns_file="${SCRUB_PATTERNS_FILE:-$HOME/.config/ai-tools/scrub-patterns.txt}"
email_pattern='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

if [ ! -f "$patterns_file" ]; then
  echo "scrub-check: patterns file not found: $patterns_file" >&2
  echo "scrub-check: ask a maintainer for it; the check can't run without it" >&2
  exit 2
fi

compiled_code_dir='netsuite/restlets/FileCabinet/'
strict_patterns="$(mktemp)"
all_patterns="$(mktemp)"
trap 'rm -f "$strict_patterns" "$all_patterns"' EXIT
active_lines="$(grep -vE '^[[:space:]]*(#|$)' "$patterns_file" || true)"
{ printf '%s\n' "$active_lines" | grep -v '^code-ok:' || true; echo "$email_pattern"; } > "$strict_patterns"
{ cat "$strict_patterns"; printf '%s\n' "$active_lines" | sed -n 's/^code-ok://p'; } > "$all_patterns"

cd "$repo_dir"
files=()
code_files=()
other_files=()
while IFS= read -r -d '' file; do
  [ -f "$file" ] || continue
  files+=("$file")
  case "$file" in
    "$compiled_code_dir"*) code_files+=("$file") ;;
    *) other_files+=("$file") ;;
  esac
done < <(git ls-files -z --cached --others --exclude-standard)

if [ "${#files[@]}" -eq 0 ]; then
  echo "scrub-check: no files to check"
  exit 0
fi

hits="$(
  if [ "${#other_files[@]}" -gt 0 ]; then grep -nHIiE -f "$all_patterns" -- "${other_files[@]}" || true; fi
  if [ "${#code_files[@]}" -gt 0 ]; then grep -nHIiE -f "$strict_patterns" -- "${code_files[@]}" || true; fi
)"
if [ -n "$hits" ]; then
  printf '%s\n' "$hits"
  echo "scrub-check: $(printf '%s\n' "$hits" | wc -l | tr -d ' ') line(s) match blocked patterns — fix before committing" >&2
  exit 1
fi
echo "scrub-check: clean (${#files[@]} files)"
