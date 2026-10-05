#!/bin/sh
# Wrap a CPBC benefit-feed JSON file in the envelope editester expects:
#   { "data": [...], "today": "<ISO-8601-Z>" }
#
# If the input file is already wrapped (top-level object with a "data" array),
# it's passed through unchanged (only `today` is added/updated to the current
# UTC date if not already present).
#
# Usage:
#   wrap-data.sh <input.json> [output-file.json]
#
# With one arg, writes <input-basename>.wrapped.json next to the input and
# prints that path on stdout (so callers can capture it). With two args,
# writes to the second path and prints that path on stdout.

set -eu

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  printf 'usage: %s <input.json> [output.json]\n' "$(basename "$0")" >&2
  exit 1
fi

input="$1"
if [ ! -f "$input" ]; then
  printf 'wrap-data.sh: input not found: %s\n' "$input" >&2
  exit 1
fi

if [ $# -eq 2 ]; then
  output="$2"
else
  case "$input" in
    *.json)      output="${input%.json}.wrapped.json" ;;
    *)           output="${input}.wrapped.json" ;;
  esac
fi

today="$(date -u +%Y-%m-%dT00:00:00.000Z)"

jq --arg today "$today" '
  if type == "array" then
    { data: ., today: $today }
  elif type == "object" and (.data | type == "array") then
    . + { today: ((.today // $today)) }
  else
    error("wrap-data.sh: unrecognized input shape (expected array or { data: [] })")
  end
' "$input" > "$output"

printf '%s\n' "$output"
