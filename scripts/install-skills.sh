#!/usr/bin/env bash
# Symlinks every skill in this repo into Claude Code's skills folder. Never overwrites: a
# skill name that already exists there (and isn't our link) is reported and skipped.
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
target_dir="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
mkdir -p "$target_dir"
skipped=0

for skill_dir in "$repo_dir"/skills/*/; do
  skill_dir="${skill_dir%/}"
  name="$(basename "$skill_dir")"
  link="$target_dir/$name"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$skill_dir" ]; then
    echo "ok       $name (already linked)"
  elif [ -e "$link" ] || [ -L "$link" ]; then
    echo "skipped  $name: $link already exists. Move it aside and re-run." >&2
    skipped=1
  else
    ln -s "$skill_dir" "$link"
    echo "linked   $name"
  fi
done

exit "$skipped"
