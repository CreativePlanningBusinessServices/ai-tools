#!/usr/bin/env bash
# bfo-to-html.sh — turns NetSuite's merged BFO XML (<pdf>, <pdfset> of <pdf>, or <pdfset> of <html>) into browser HTML.
# usage: bfo-to-html.sh <merged.xml> <out.html>
# Exit 0 = written, 1 = transform failed (xsltproc's message is shown), 2 = usage/input.
set -uo pipefail

usage() { echo "usage: bfo-to-html.sh <merged.xml> <out.html>" >&2; exit 2; }
[ $# -eq 2 ] || usage
input_file="$1"; output_file="$2"
if [ ! -f "$input_file" ] || [ ! -r "$input_file" ]; then echo "bfo-to-html: cannot read $input_file" >&2; exit 2; fi
for tool in xsltproc jq awk; do
  command -v "$tool" >/dev/null 2>&1 || { echo "bfo-to-html: $tool is required" >&2; exit 2; }
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
data_file="$script_dir/../data/bfo-support.json"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# Entities that have a browser glyph map to it; the rest stay visible as literal "&name;" text rather than silently vanishing.
# The doubled &#38;#38; survives the declaration-time expansion of character references.
jq -r '{nbsp:160,copy:169,reg:174,trade:8482,mdash:8212,ndash:8211,bull:8226,hellip:8230,middot:183,
    lsquo:8216,rsquo:8217,ldquo:8220,rdquo:8221,sbquo:8218,bdquo:8222,deg:176,euro:8364,pound:163,yen:165,cent:162,
    times:215,divide:247,plusmn:177,laquo:171,raquo:187,sect:167,para:182,frac12:189,frac14:188,frac34:190,
    sup1:185,sup2:178,sup3:179,micro:181,shy:173,zwnj:8204,zwj:8205,lrm:8206,rlm:8207,minus:8722,le:8804,ge:8805,
    ne:8800,larr:8592,rarr:8594,uarr:8593,darr:8595,dagger:8224,Dagger:8225,permil:8240,prime:8242,Prime:8243,
    lsaquo:8249,rsaquo:8250,iexcl:161,iquest:191,not:172,macr:175,acute:180,uml:168,cedil:184,ordf:170,ordm:186,
    curren:164,brvbar:166,zwnbsp:65279} as $codepoint
  | "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE pdf [" + ([.entities[] | select(IN("amp", "lt", "gt", "quot", "apos") | not)
  | "<!ENTITY \(.) \"" + (if $codepoint[.] then "&#\($codepoint[.]);" else "&#38;#38;\(.);" end) + "\">"] | join("")) + "]>"' \
  "$data_file" > "$work/prolog.xml" || { echo "bfo-to-html: $data_file is not usable" >&2; exit 2; }

# The DOCTYPE names an external DTD, so it goes; the entity prolog takes its place.
awk '
  NR == 1 { while ((getline prolog < prologFile) > 0) print prolog }
  !inRoot {
    while (match($0, /<\?xml[^>]*\?>|<!DOCTYPE[^>]*>/)) $0 = substr($0, 1, RSTART - 1) substr($0, RSTART + RLENGTH)
    if ($0 ~ /<[a-zA-Z]/) inRoot = 1
  }
  { print }' prologFile="$work/prolog.xml" "$input_file" > "$work/prepared.xml"

if ! xsltproc --nonet -o "$work/out.html" "$script_dir/bfo-to-html.xsl" "$work/prepared.xml" 2> "$work/xsltproc.err"; then
  echo "bfo-to-html: transform failed: $(tr '\n' ' ' < "$work/xsltproc.err")" >&2
  exit 1
fi
mv "$work/out.html" "$output_file"
