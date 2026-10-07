#!/usr/bin/env bash
# Insert the email-designer preview banner after the opening <body> tag (or at the top when there
# is none), editing the file in place.
#
# Usage: preview-banner.sh <preview.html> <subject> <account alias> <sample> <mode>
set -euo pipefail
[ $# -eq 5 ] || { echo "usage: preview-banner.sh <preview.html> <subject> <account alias> <sample> <mode>" >&2; exit 1; }
[ -f "$1" ] || { echo "preview-banner: no such file: $1" >&2; exit 1; }

# Values travel through ENVIRON, not awk -v, so backslashes in a subject arrive unmangled.
BANNER_SUBJECT="$2" BANNER_ACCOUNT="$3" BANNER_SAMPLE="$4" BANNER_MODE="$5" awk '
  { html = (NR == 1) ? $0 : html "\n" $0 }
  END {
    banner = "<div style=\"font:13px/1.4 -apple-system,sans-serif;background:#fff7e6;border-bottom:1px solid #e6c576;padding:8px 12px\">" \
      "<b>Subject:</b> " ENVIRON["BANNER_SUBJECT"] " &nbsp;·&nbsp; <b>Account:</b> " ENVIRON["BANNER_ACCOUNT"] \
      " &nbsp;·&nbsp; <b>Sample:</b> " ENVIRON["BANNER_SAMPLE"] " &nbsp;·&nbsp; <b>Mode:</b> " ENVIRON["BANNER_MODE"] \
      " &nbsp;·&nbsp; Preview only — contains live record data, do not share</div>"
    if (match(html, /<[bB][oO][dD][yY]([ \t\r\n][^>]*)?>/)) {
      print substr(html, 1, RSTART + RLENGTH - 1) banner substr(html, RSTART + RLENGTH)
    } else {
      print banner html
    }
  }' "$1" > "$1.banner"
mv "$1.banner" "$1"
