#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
data="$here/../skills/netsuite-pdf-designer/data/bfo-support.json"
refs="$here/../skills/netsuite-pdf-designer/references"

if [ ! -f "$data" ]; then fail "bfo-support.json exists"; finish; fi
if ! jq -e . "$data" >/dev/null 2>&1; then fail "bfo-support.json parses with jq"; finish; fi
pass "bfo-support.json parses with jq"

allowed='["supported","partial","unsupported","unverified"]'

assert_eq "$(jq -r '.version' "$data")" 1 "version is 1"

bad_element_status="$(jq -r --argjson ok "$allowed" '.elements | to_entries[] | select(.value.status as $s | $ok | index($s) | not) | .key' "$data")"
assert_eq "$bad_element_status" "" "every element status is in the allowed set"
bad_attr_status="$(jq -r --argjson ok "$allowed" '.elements | to_entries[] | .key as $el | (.value.attributes // {}) | to_entries[] | select(.value as $s | $ok | index($s) | not) | "\($el).\(.key)"' "$data")"
assert_eq "$bad_attr_status" "" "every attribute status is in the allowed set"
bad_global_status="$(jq -r --argjson ok "$allowed" '.globalAttributes | to_entries[] | select(.value as $s | $ok | index($s) | not) | .key' "$data")"
assert_eq "$bad_global_status" "" "every global attribute status is in the allowed set"
bad_css_status="$(jq -r --argjson ok "$allowed" '.css | to_entries[] | select(.value.status as $s | $ok | index($s) | not) | .key' "$data")"
assert_eq "$bad_css_status" "" "every css status is in the allowed set"
bad_css_value="$(jq -r --argjson ok "$allowed" '.css | to_entries[] | .key as $prop | (.value.values // {}) | to_entries[] | select(.value as $s | $ok | index($s) | not) | "\($prop).\(.key)"' "$data")"
assert_eq "$bad_css_value" "" "every css value status is in the allowed set"

missing_element_source="$(jq -r '.elements | to_entries[] | select((.value.source // "") == "") | .key' "$data")"
assert_eq "$missing_element_source" "" "every element has a non-empty source"
missing_css_source="$(jq -r '.css | to_entries[] | select((.value.source // "") == "") | .key' "$data")"
assert_eq "$missing_css_source" "" "every css entry has a non-empty source"
unresolved_source="$(jq -r '.sources as $known | ([.elements[], .css[]] | map(.source) | unique[]) | . as $src | select(($src | startswith("http")) or ($known | has($src)) | not)' "$data")"
assert_eq "$unresolved_source" "" "every source is a key in sources or a URL"
unverified_without_note="$(jq -r '[.elements, .css] | .[] | to_entries[] | select(.value.status == "unverified" and ((.value.note // "") == "")) | .key' "$data")"
assert_eq "$unverified_without_note" "" "every unverified entry carries a note"

for source_key in bfo-tags bfo-css netsuite-help; do
  assert_eq "$(jq -r --arg key "$source_key" '.sources[$key] // "" | startswith("http")' "$data")" true "sources.$source_key is a URL"
done

assert_eq "$(jq -r '.css.display.values | has("flex")' "$data")" true "css.display.values.flex is present"
assert_eq "$(jq -r '.css.display.values | has("grid")' "$data")" true "css.display.values.grid is present"
assert_eq "$(jq -r '.css.display.values.flex' "$data")" unsupported "display:flex is unsupported (sandbox probe)"
assert_eq "$(jq -r '.css["border-radius"].status' "$data")" unsupported "border-radius is unsupported (sandbox probe)"
assert_eq "$(jq -r '.css["background-image"].status' "$data")" supported "background-image is supported (sandbox probe)"
assert_eq "$(jq -r '.css.position.values.absolute' "$data")" partial "position:absolute is partial (needs a relative ancestor)"
assert_eq "$(jq -r '.lengthUnits.unsupported | index("rem") != null' "$data")" true "rem is listed as an unsupported unit"

missing_effect="$(jq -r '.css | to_entries[] | select((.value.status == "unsupported" or .value.status == "partial") and ((.value.effect // "") | IN("ignored","breaks","unknown") | not)) | .key' "$data")"
assert_eq "$missing_effect" "" "every unsupported/partial css entry has an effect"
missing_value_effect="$(jq -r '.css | to_entries[] | .key as $prop | .value as $entry | ($entry.values // {}) | to_entries[] | select(.value == "unsupported" or .value == "partial") | select(($entry.valueEffects[.key] // "") | IN("ignored","breaks","unknown") | not) | "\($prop).\(.key)"' "$data")"
assert_eq "$missing_value_effect" "" "every unsupported/partial css value has an effect"
missing_attr_effect="$(jq -r '.elements | to_entries[] | .key as $el | .value as $entry | ($entry.attributes // {}) | to_entries[] | select(.value == "unsupported" or .value == "partial") | select(($entry.attributeEffects[.key] // "") | IN("ignored","breaks","unknown") | not) | "\($el).\(.key)"' "$data")"
assert_eq "$missing_attr_effect" "" "every unsupported/partial attribute has an effect"
assert_eq "$(jq -r '.css.display.valueEffects.flex' "$data")" ignored "display:flex is ignored (sandbox probe)"
assert_eq "$(jq -r '.css.display.valueEffects.grid' "$data")" ignored "display:grid is ignored (sandbox probe)"
assert_eq "$(jq -r '.css["border-radius"].effect' "$data")" ignored "border-radius is ignored (sandbox probe)"
assert_eq "$(jq -r '.css.position.valueEffects.absolute' "$data")" breaks "position:absolute breaks the render (sandbox probe)"
assert_eq "$(jq -r '.entityStatus.nbsp.status + " " + .entityStatus.nbsp.source' "$data")" "supported netsuite-probe-2026-10" "nbsp works (a production invoice template)"
for element in pdf pdfset html head body macrolist macro pbr pagenumber totalpages barcode link table thead tbody tfoot tr td th img div p span br ul ol li; do
  assert_eq "$(jq -r --arg el "$element" '.elements | has($el)' "$data")" true "element <$element> is listed"
done
assert_eq "$(jq -r '.elements.html.status' "$data")" supported "<html> is supported"
assert_eq "$(jq -r '.elements.html.source' "$data")" netsuite-probe-2026-10 "<html> support comes from the sandbox probe"

assert_eq "$(jq -r '.entities | index("nbsp") != null' "$data")" true "entities contains nbsp"
assert_eq "$(jq -r '.entities | index("copy") != null' "$data")" true "entities contains copy"
assert_eq "$(jq -r '.entities | index("reg") != null' "$data")" true "entities contains reg"
assert_eq "$(jq -r '.entities | length >= 246' "$data")" true "entities holds the full BFO list"

for directive in if list attempt; do
  assert_eq "$(jq -r --arg name "$directive" '.freemarker.directives | index($name) != null' "$data")" true "freemarker directive $directive"
done
for builtin in has_content string c; do
  assert_eq "$(jq -r --arg name "$builtin" '.freemarker.builtins | index($name) != null' "$data")" true "freemarker built-in $builtin"
done

for doc in bfo.md freemarker.md; do
  [ -f "$refs/$doc" ] && pass "references/$doc exists" || fail "references/$doc exists"
  lines="$(wc -l < "$refs/$doc" 2>/dev/null || echo 9999)"
  [ "$lines" -le 260 ] && pass "references/$doc stays under about 250 lines ($lines)" || fail "references/$doc is too long ($lines lines)"
done

finish
