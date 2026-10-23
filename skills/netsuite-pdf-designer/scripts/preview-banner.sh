#!/usr/bin/env bash
# Insert the PDF-designer preview banner after the opening <body> tag (or at the top when there
# is none), editing the file in place.
#
# Usage: preview-banner.sh <preview.html> <title> <account alias> <sample> <mode>
set -euo pipefail
[ $# -eq 5 ] || { echo "usage: preview-banner.sh <preview.html> <title> <account alias> <sample> <mode>" >&2; exit 1; }
[ -f "$1" ] || { echo "preview-banner: no such file: $1" >&2; exit 1; }

# Values travel through ENVIRON, not awk -v, so backslashes in a title arrive unmangled.
BANNER_TITLE="$2" BANNER_ACCOUNT="$3" BANNER_SAMPLE="$4" BANNER_MODE="$5" awk '
  function escape(text) {
    gsub(/&/, "\\&amp;", text); gsub(/</, "\\&lt;", text); gsub(/>/, "\\&gt;", text)
    return text
  }
  { html = (NR == 1) ? $0 : html "\n" $0 }
  END {
    banner = "<div style=\"font:13px/1.4 -apple-system,sans-serif;background:#fff7e6;border-bottom:1px solid #e6c576;padding:8px 12px\">" \
      "<b>Template:</b> " escape(ENVIRON["BANNER_TITLE"]) " &nbsp;·&nbsp; <b>Account:</b> " escape(ENVIRON["BANNER_ACCOUNT"]) \
      " &nbsp;·&nbsp; <b>Sample:</b> " escape(ENVIRON["BANNER_SAMPLE"]) " &nbsp;·&nbsp; <b>Mode:</b> " escape(ENVIRON["BANNER_MODE"]) \
      " &nbsp;·&nbsp; Preview only — contains live record data, do not share" \
      " &nbsp;·&nbsp; Page flow, repeated headers and fonts are exact only in the PDF.</div>"
    if (match(html, /<[bB][oO][dD][yY]([ \t\r\n][^>]*)?>/)) {
      print substr(html, 1, RSTART + RLENGTH - 1) banner substr(html, RSTART + RLENGTH)
    } else {
      print banner html
    }
  }' "$1" > "$1.banner"
mv "$1.banner" "$1"
