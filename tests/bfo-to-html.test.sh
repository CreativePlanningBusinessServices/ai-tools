#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
twin_script="$here/../skills/netsuite-pdf-designer/scripts/bfo-to-html.sh"
banner_script="$here/../skills/netsuite-pdf-designer/scripts/preview-banner.sh"
fixtures="$here/fixtures/pdf"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# offset_of <haystack> <needle>: character offset of the first occurrence (the whole length when absent)
offset_of() { local before="${1%%"$2"*}"; echo "${#before}"; }
assert_before() {
  if [ "$(offset_of "$1" "$2")" -lt "$(offset_of "$1" "$3")" ] && [ "$(offset_of "$1" "$3")" -lt "${#1}" ]; then pass "$4"; else fail "$4"; fi
}

bash "$twin_script" "$fixtures/merged.xml" "$tmp/merged.html"; status=$?
assert_eq "$status" 0 "merged.xml converts"
twin="$(cat "$tmp/merged.html")"
if xmllint --html --noout "$tmp/merged.html" 2> "$tmp/lint.err" && [ ! -s "$tmp/lint.err" ]; then pass "the twin is well-formed HTML"; else fail "the twin is well-formed HTML ($(cat "$tmp/lint.err"))"; fi

assert_before "$twin" "Header Company Name" "INVOICE #" "the header macro comes before the first table"
assert_before "$twin" "Copy &amp; Print" "Footer Marker" "the footer macro comes after the last table"
for leftover in "<macrolist" "<pdf" "<link name=" "<macro " "<pbr" "<pagenumber" "<totalpages" "<barcode"; do
  assert_not_contains "$twin" "$leftover" "no $leftover element is left"
done
assert_contains "$twin" 'class="bfo-pbr"' "<pbr/> becomes a bfo-pbr element"
assert_contains "$twin" '<span class="bfo-pagenumber">1</span> of <span class="bfo-totalpages">N</span>' "the page number shows 1 and the total N"
assert_contains "$twin" "INV60699</span>" "the barcode shows its value"
assert_contains "$twin" "code128" "the barcode shows its type"
assert_contains "$twin" 'data-bfo="/pdf/body/table[2]/tr[1]/td[1]"' "the second table's first cell carries its BFO path"
assert_contains "$twin" 'data-bfo="/pdf/head/macrolist/macro[1]/table[1]/tr[1]/td[1]"' "macro content carries its BFO path"
assert_contains "$twin" "width: 8.5in" "the sheet is Letter wide"
assert_not_contains "$twin" 'class="bfo-size-note"' "a known size has no note"
assert_contains "$twin" "font-family: NotoSans" "the template's style block is kept"
assert_contains "$twin" $'\xc2\xa0' "&nbsp; becomes a non-breaking space"

sed 's/size="Letter"/size="A4"/' "$fixtures/merged.xml" > "$tmp/a4.xml"
bash "$twin_script" "$tmp/a4.xml" "$tmp/a4.html"
assert_contains "$(cat "$tmp/a4.html")" "width: 210mm" "size=A4 gives 210mm"

sed 's/size="Letter"/size="Letter-landscape"/' "$fixtures/merged.xml" > "$tmp/landscape.xml"
bash "$twin_script" "$tmp/landscape.xml" "$tmp/landscape.html"
assert_contains "$(cat "$tmp/landscape.html")" "width: 11in" "Letter-landscape is 11in wide"

sed 's/size="Letter"/size="Tabloid"/' "$fixtures/merged.xml" > "$tmp/unknown.xml"
bash "$twin_script" "$tmp/unknown.xml" "$tmp/unknown.html"
unknown_twin="$(cat "$tmp/unknown.html")"
assert_contains "$unknown_twin" "width: 8.5in" "an unknown size falls back to Letter"
assert_contains "$unknown_twin" 'class="bfo-size-note"' "an unknown size gets a note"
assert_contains "$unknown_twin" "Tabloid" "the note names the size"

bash "$twin_script" "$fixtures/merged-statements.xml" "$tmp/statements.html"; status=$?
assert_eq "$status" 0 "a <pdfset> of <html> converts"
statements="$(cat "$tmp/statements.html")"
assert_contains "$statements" "Statement One Cell" "the first statement renders"
assert_contains "$statements" "Statement Two Cell" "the second statement renders"
assert_eq "$(grep -o 'class="bfo-sheet"' "$tmp/statements.html" | wc -l | tr -d ' ')" 2 "one sheet per statement"
assert_contains "$statements" 'data-bfo="/pdfset/html[2]/body/table[1]/tr[1]/td[1]"' "the second statement's cell path reflects the real structure"
assert_contains "$statements" "Statement Footer" "a statement's footer macro is used"

bash "$twin_script" "$fixtures/merged-pdfset-pdf.xml" "$tmp/packets.html"; status=$?
assert_eq "$status" 0 "a <pdfset> of <pdf> converts"
packets="$(cat "$tmp/packets.html")"
assert_eq "$(grep -o 'class="bfo-sheet"' "$tmp/packets.html" | wc -l | tr -d ' ')" 2 "one sheet per packet"
assert_contains "$packets" 'data-bfo="/pdfset/pdf[2]/body/p[1]"' "a packet's path names its pdf position"

bash "$twin_script" > /dev/null 2>&1; assert_eq "$?" 2 "no arguments is a usage error (2)"
bash "$twin_script" "$tmp/missing.xml" "$tmp/x.html" > /dev/null 2>&1; assert_eq "$?" 2 "a missing input is a usage error (2)"
printf '<pdf><body><p>unclosed</body></pdf>' > "$tmp/broken.xml"
message="$(bash "$twin_script" "$tmp/broken.xml" "$tmp/broken.html" 2>&1)"; status=$?
assert_eq "$status" 1 "malformed XML exits 1"
assert_contains "$message" "bfo-to-html" "the failure message names the script"
assert_contains "$message" "parser error" "the failure message carries xsltproc's error"

# A ~3 MB merged document converts in under 15 s.
{
  sed -n '1,/<\/style>/p' "$fixtures/merged.xml"
  echo '</head><body header="nlheader" size="Letter"><table>'
  for block in $(seq 1 300); do
    for row in $(seq 1 100); do
      echo "<tr><td>Line item $block-$row with some descriptive text</td><td align=\"right\">\$$row.00</td><td>Extra cell padding text</td></tr>"
    done
  done
  echo '</table></body></pdf>'
} > "$tmp/big.xml"
sed -i.bak 's|<link name="NotoSans"[^>]*/>||' "$tmp/big.xml"
echo "fixture size: $(wc -c < "$tmp/big.xml") bytes"
start_seconds=$SECONDS
bash "$twin_script" "$tmp/big.xml" "$tmp/big.html"; status=$?
elapsed=$((SECONDS - start_seconds))
assert_eq "$status" 0 "the 3 MB fixture converts"
if [ "$elapsed" -lt 15 ]; then pass "the 3 MB fixture converts in under 15 s (${elapsed}s)"; else fail "the 3 MB fixture took ${elapsed}s"; fi

# Banner
printf '<html><body class="x"><p>hi</p></body></html>' > "$tmp/banner.html"
bash "$banner_script" "$tmp/banner.html" "ACS | Standard Invoice" sb2 "invoice 123" saved; status=$?
assert_eq "$status" 0 "the banner is inserted"
banner_out="$(cat "$tmp/banner.html")"
assert_contains "$banner_out" "ACS | Standard Invoice" "the banner shows the title"
assert_contains "$banner_out" "sb2" "the banner shows the alias"
assert_contains "$banner_out" "invoice 123" "the banner shows the sample"
assert_contains "$banner_out" "saved" "the banner shows the mode"
assert_contains "$banner_out" "Preview only — contains live record data, do not share" "the banner carries the live-data warning"
assert_contains "$banner_out" "Page flow, repeated headers and fonts are exact only in the PDF." "the banner carries the fidelity warning"
assert_contains "$banner_out" '<body class="x"><div' "the banner goes straight after <body>"
assert_contains "$banner_out" "<p>hi</p>" "the page content is kept"

printf '<p>no body here</p>' > "$tmp/nobody.html"
bash "$banner_script" "$tmp/nobody.html" "Title & <b>" sb2 sample draft
nobody_out="$(cat "$tmp/nobody.html")"
assert_contains "$nobody_out" "Preview only" "a file without <body> gets the banner"
assert_eq "${nobody_out:0:4}" "<div" "the banner is prepended when there is no <body>"
assert_contains "$nobody_out" "Title &amp; &lt;b&gt;" "banner values are HTML-escaped"
bash "$banner_script" "$tmp/nobody.html" a b >/dev/null 2>&1; assert_eq "$?" 1 "a wrong argument count is rejected"

finish
