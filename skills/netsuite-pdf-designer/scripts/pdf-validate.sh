#!/usr/bin/env bash
# pdf-validate.sh — checks a NetSuite Advanced PDF/HTML template (FreeMarker + BFO XML) before it reaches NetSuite.
# usage: pdf-validate.sh [--merged] [--json] [--data <bfo-support.json>] <file>
# Prints "ERROR|WARN <line>:<col> <rule> <message>" per finding and a summary; exit 0 = no ERROR, 1 = ERROR, 2 = usage/input.
set -uo pipefail

usage() { echo "usage: pdf-validate.sh [--merged] [--json] [--data <bfo-support.json>] <file>" >&2; exit 2; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
data_file="$script_dir/../data/bfo-support.json"
merged=0; json=0; input_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --merged) merged=1 ;;
    --json) json=1 ;;
    --data) [ $# -ge 2 ] || usage; data_file="$2"; shift ;;
    -*) usage ;;
    *) [ -z "$input_file" ] || usage; input_file="$1" ;;
  esac
  shift
done
[ -n "$input_file" ] || usage
if [ ! -f "$input_file" ] || [ ! -r "$input_file" ]; then echo "pdf-validate: cannot read $input_file" >&2; exit 2; fi
command -v xmllint >/dev/null 2>&1 || { echo "pdf-validate: xmllint is required" >&2; exit 2; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

if ! jq -e '(.elements|type) == "object" and (.css|type) == "object" and (.globalAttributes|type) == "object"
    and (.lengthUnits|type) == "object" and (.entities|type) == "array"
    and (.freemarker.builtins|type) == "array" and (.freemarker.directives|type) == "array"' \
    "$data_file" >/dev/null 2>&1; then
  echo "pdf-validate: $data_file is not a usable bfo-support.json" >&2; exit 2
fi
jq -r '
  (.elements | to_entries[] | ["E", .key, .value.status, (.value.effect // "unknown")]),
  (.elements | to_entries[] | .key as $element | (.value.attributeEffects // {}) as $effects
    | (.value.attributes // {}) | to_entries[] | ["A", $element, .key, .value, ($effects[.key] // "unknown")]),
  (.globalAttributes | to_entries[] | ["G", .key, .value]),
  (.css | to_entries[] | ["C", .key, .value.status, (.value.effect // "unknown")]),
  (.css | to_entries[] | .key as $property | .value as $entry | ($entry.values // {}) | to_entries[]
    | ["V", $property, .key, .value, (($entry.valueEffects // {})[.key] // $entry.effect // "unknown")]),
  (.lengthUnits | to_entries[] | select(.value | type == "array") | .key as $status | .value[] | ["U", ., $status]),
  ((.selectors.unsupported // [])[] | ["S", .]),
  (.freemarker.builtins[] | ["B", .]),
  (.freemarker.directives[] | ["D", .])
  | @tsv' "$data_file" > "$work/data.tsv"
# One prolog line declares every BFO named entity, so &nbsp; and friends parse; it is subtracted from xmllint's line numbers.
jq -r '"<?xml version=\"1.0\"?><!DOCTYPE pdf [" + ([.entities[] | select(IN("amp", "lt", "gt", "quot", "apos") | not)
  | "<!ENTITY \(.) \"&#160;\">"] | join("")) + "]>"' "$data_file" > "$work/prolog.xml"

stripped="$work/stripped.xml"; xml_copy="$work/xml-copy.xml"; findings="$work/findings.tsv"
: > "$stripped"; : > "$xml_copy"; : > "$findings"
if ! grep -q '[^[:space:]]' "$input_file"; then
  printf 'ERROR\t1\t1\tenvelope.empty\tthe template is empty\n' > "$findings"
else
  if [ "$merged" -eq 1 ]; then
    cp "$input_file" "$stripped"; cp "$input_file" "$xml_copy"
  else
    # FreeMarker pass: writes $stripped (FreeMarker blanked, every branch kept) and $xml_copy (non-first branches blanked
    # too), both with the source's lines and columns.
    awk -v strippedFile="$stripped" -v xmlCopyFile="$xml_copy" -v corruptFile="$work/corrupt" -v declarationFile="$work/declaration-after-freemarker" \
      -f "$script_dir/pdf-freemarker.awk" "$work/data.tsv" "$input_file" >> "$findings"
  fi
  awk -v declarationAfterFreemarker="$([ -f "$work/declaration-after-freemarker" ] && echo 1)" -f "$script_dir/pdf-bfo.awk" "$work/data.tsv" "$stripped" >> "$findings"

  # XML pass: xmllint reads the branch-blanked copy behind a one-line prolog. Entity errors are all reported; for
  # structure only the first error is, since libxml2 cascades after it.
  if [ ! -f "$work/corrupt" ]; then
    awk 'function blanks(count) { return sprintf("%" count "s", "") }
      NR == 1 { while ((getline prolog < prologFile) > 0) print prolog }
      !inRoot {
        while (match($0, /<\?xml[^>]*\?>|<!DOCTYPE[^>]*>/)) $0 = substr($0, 1, RSTART - 1) blanks(RLENGTH) substr($0, RSTART + RLENGTH)
        if ($0 ~ /<[a-zA-Z]/) inRoot = 1
      }
      { print }' prologFile="$work/prolog.xml" "$xml_copy" > "$work/xmllint.xml"
    xmllint --noout --nonet "$work/xmllint.xml" 2> "$work/xmllint.err"
    awk -v prologLines="$(wc -l < "$work/prolog.xml")" -f "$script_dir/pdf-xmllint.awk" "$xml_copy" "$work/xmllint.err" >> "$findings"
  fi
fi

tab="$(printf '\t')"
sort -s -t "$tab" -k2,2n -k3,3n "$findings" > "$work/sorted.tsv"
error_count="$(grep -c "^ERROR$tab" "$work/sorted.tsv")"
warning_count="$(grep -c "^WARN$tab" "$work/sorted.tsv")"
if [ "$json" -eq 1 ]; then
  jq -R -s 'split("\n") | map(select(length > 0) | split("\t")
    | {severity: .[0], line: (.[1] | tonumber), col: (.[2] | tonumber), rule: .[3], message: .[4]})' "$work/sorted.tsv"
else
  awk -F '\t' '{ printf "%s %s:%s %s %s\n", $1, $2, $3, $4, $5 }' "$work/sorted.tsv"
  echo "$error_count errors, $warning_count warnings"
fi
[ "$error_count" -eq 0 ]
