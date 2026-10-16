#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
validator="$here/../skills/netsuite-pdf-designer/scripts/pdf-validate.sh"
fixtures="$here/fixtures/pdf"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# run_validator <args...>: sets $output and $status
run_validator() { output="$(bash "$validator" "$@" 2>&1)"; status=$?; }
# assert_line <regex> <name>: some output line matches the extended regex
assert_line() {
  if printf '%s\n' "$output" | grep -Eq "$1"; then pass "$2"; else fail "$2 (no line matching '$1' in: $output)"; fi
}

run_validator "$fixtures/good.xml"
assert_eq "$status" 0 "good.xml exits 0"
assert_contains "$output" "0 errors, 0 warnings" "good.xml has no findings"
assert_not_contains "$output" "nbsp" "&nbsp; is not flagged"

run_validator "$fixtures/no-doctype.xml"
assert_eq "$status" 1 "a missing DOCTYPE exits 1"
assert_line '^ERROR 1:1 envelope\.doctype ' "a missing DOCTYPE is reported at 1:1"

run_validator "$fixtures/root-html.xml"
assert_line '^ERROR 2:1 envelope\.root ' "an <html> root is an envelope error"

run_validator "$fixtures/fm-unclosed-if.xml"
assert_eq "$status" 1 "an unclosed <#if> exits 1"
assert_line '^ERROR 12:1 freemarker\.unclosed <#if>' "an unclosed <#if> is reported where it opens"

run_validator "$fixtures/fm-stray-close.xml"
assert_line '^ERROR 10:1 freemarker\.stray </#list>' "a stray </#list> is reported"

run_validator "$fixtures/fm-else-outside.xml"
assert_line '^ERROR 8:1 freemarker\.misplaced <#else>' "<#else> outside an <#if> is reported"

run_validator "$fixtures/fm-open-interpolation.xml"
assert_line '^ERROR 7:4 freemarker\.interpolation ' "an unclosed \${ is reported where it opens"

run_validator "$fixtures/fm-open-comment.xml"
assert_line '^ERROR 7:1 freemarker\.comment ' "an unterminated <#-- is reported where it opens"

run_validator "$fixtures/fm-builtin.xml"
assert_eq "$status" 0 "an unknown built-in alone exits 0"
assert_line '^WARN 7:19 freemarker\.builtin .*nosuchbuiltin' "an unknown built-in is a warning"

run_validator "$fixtures/xml-unclosed-td.xml"
assert_eq "$status" 1 "an unclosed <td> exits 1"
assert_line '^ERROR 20:2 xml\.' "an unclosed <td> is reported at its source line and column"

run_validator "$fixtures/xml-bare-amp.xml"
assert_eq "$status" 1 "a bare & exits 1"
assert_line '^ERROR 7:9 xml\.' "a bare & is reported at its source line and column"

run_validator "$fixtures/bfo.xml"
assert_eq "$status" 0 "bfo warnings alone exit 0"
assert_line '^WARN 10:1 bfo\.element .*blink' "<blink> is unknown to the BFO data"
assert_line '^WARN 11:28 bfo\.css-value .*display:flex' "display:flex is an ignored value"
assert_line '^WARN 6:10 bfo\.unit .*rem' "rem units are ignored"
text_count="$(printf '%s\n' "$output" | grep -Ec '^(ERROR|WARN) ')"
run_validator --json "$fixtures/bfo.xml"
assert_eq "$(printf '%s' "$output" | jq -r 'type')" array "--json prints a JSON array"
assert_eq "$(printf '%s' "$output" | jq -r 'length')" "$text_count" "--json has the same findings as the text output"
assert_eq "$(printf '%s' "$output" | jq -r '.[0] | keys | join(",")')" "col,line,message,rule,severity" "--json objects carry the five fields"

run_validator "$fixtures/position.xml"
assert_eq "$status" 0 "position:absolute is a warning, not an error"
assert_line '^WARN 7:13 bfo\.position ' "position:absolute without a relative ancestor is reported"
assert_eq "$(printf '%s\n' "$output" | grep -c 'bfo\.position')" 1 "position:absolute inside a relative parent is not reported"
assert_not_contains "$output" "bfo.css-value" "position:relative is not reported"

run_validator "$fixtures/unclosed-br.xml"
assert_eq "$status" 1 "an unclosed <br> exits 1"
assert_line '^ERROR 7:12 xml\.' "an unclosed <br> is an XML error at the <br>"

run_validator "$fixtures/image-http.xml"
assert_line '^WARN 7:6 netsuite\.image-http ' "an http: image is a warning"

run_validator "$fixtures/no-nsfont.xml"
assert_line '^WARN 3:1 netsuite\.nsfont ' "a head without an nsfont link is a warning"

run_validator --merged "$fixtures/fm-unclosed-if.xml"
assert_not_contains "$output" "freemarker." "--merged skips the freemarker rules"

run_validator --merged "$fixtures/merged-pdfset.xml"
assert_eq "$status" 0 "--merged accepts <pdfset> holding <html> documents"
assert_not_contains "$output" "envelope." "a <pdfset> of <html> documents passes the envelope"

run_validator "$fixtures/branch-alternative-rows.xml"
assert_eq "$status" 0 "a <tr> opened differently in <#if>/<#else> exits 0"
assert_not_contains "$output" "xml." "alternative row openers are not an XML error"
run_validator "$fixtures/branch-alternative-attributes.xml"
assert_eq "$status" 0 "alternative attributes and <#switch>/<#attempt> branches exit 0"
assert_not_contains "$output" "xml." "an attribute set in both branches is not 'redefined'"

run_validator "$fixtures/freemarker-idioms.xml"
assert_eq "$status" 0 "camelCase directives, ?exists, &copy; and < inside \${} exit 0"
assert_contains "$output" "0 errors, 0 warnings" "the FreeMarker idioms fixture has no findings"
assert_not_contains "$output" "copy" "&copy; is not flagged"

run_validator "$fixtures/assign-before-declaration.xml"
assert_not_contains "$output" "envelope.xml-declaration" "a FreeMarker directive before <?xml on line 1 is accepted"

run_validator "$fixtures/div-text.xml"
assert_line '^WARN 7:32 netsuite\.div-text ' "bare text inside <div> is a warning"

run_validator "$fixtures/xml-unknown-entity.xml"
assert_line '^ERROR 7:10 xml\.entity .*&euro2;' "an unknown entity is an XML error at its &"
assert_line '^ERROR 7:22 xml\.entity .*&bogus;' "every unknown entity is reported"

run_validator "$fixtures/multiline-directive.xml"
assert_line '^ERROR 10:9 xml\.entity ' "lines stay mapped after a multi-line directive"

: > "$tmp/empty.xml"
run_validator "$tmp/empty.xml"
assert_eq "$status" 1 "an empty file exits 1"
assert_line '^ERROR 1:1 envelope\.empty ' "an empty file is an envelope error"
printf '  \n\t\n' > "$tmp/blank.xml"
run_validator "$tmp/blank.xml"
assert_line '^ERROR 1:1 envelope\.empty ' "a whitespace-only file is an envelope error"
assert_contains "$output" "1 errors, 0 warnings" "an empty file reports only envelope.empty"

run_validator "$tmp/missing.xml"
assert_eq "$status" 2 "a missing file exits 2"
run_validator
assert_eq "$status" 2 "no file argument exits 2"
printf '{"nope": 1}\n' > "$tmp/bad-data.json"
run_validator --data "$tmp/bad-data.json" "$fixtures/good.xml"
assert_eq "$status" 2 "a bad data file exits 2"

awk '
  /<!-- items -->/ { repeating = 1 }
  repeating { block = block $0 "\n" }
  /<!-- \/items -->/ { repeating = 0; for (copy = 0; copy < 1100; copy++) printf "%s", block; next }
  !repeating { print }
' "$fixtures/good.xml" > "$tmp/large.xml"
large_size="$(wc -c < "$tmp/large.xml" | tr -d ' ')"
if [ "$large_size" -ge 150000 ]; then pass "large fixture is at least 150 KB"; else fail "large fixture is at least 150 KB (got $large_size)"; fi
started_at="$(date +%s)"
run_validator "$tmp/large.xml"
elapsed=$(( $(date +%s) - started_at ))
assert_eq "$status" 0 "the large fixture exits 0"
if [ "$elapsed" -lt 10 ]; then pass "the large fixture validates in under 10 s (${elapsed}s)"; else fail "the large fixture validates in under 10 s (took ${elapsed}s)"; fi

finish
