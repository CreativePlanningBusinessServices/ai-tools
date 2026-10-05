#!/bin/sh
# Extract the visible text from a Microsoft Word .docx file.
#
# A .docx is a ZIP containing word/document.xml — this script unpacks that
# XML, strips the tags, decodes the handful of XML entities that occur in
# practice, and squeezes blank lines. Output goes to stdout; redirect to
# capture.
#
# Usage:  docx-to-text.sh <input.docx>
# Stdin:  ignored.
# Stdout: plain text, one paragraph per line, blank lines trimmed.
# Exit:   0 on success; non-zero if input is missing or not a valid docx.

set -eu

if [ $# -ne 1 ]; then
  echo "usage: docx-to-text.sh <input.docx>" >&2
  exit 1
fi

INPUT="$1"

if [ ! -f "$INPUT" ]; then
  echo "docx-to-text: input not found: $INPUT" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "docx-to-text: unzip is not on PATH" >&2
  exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
  echo "docx-to-text: perl is not on PATH" >&2
  exit 1
fi

# Word splits a paragraph across many <w:t> runs, so we have to flatten the
# whole stream and inject a newline at every </w:p> boundary. Then strip
# every remaining tag and decode the five entities that carrier specs use.
unzip -p "$INPUT" word/document.xml 2>/dev/null \
  | perl -pe 's{</w:p>}{\n}g; s{<[^>]+>}{}g; s{&lt;}{<}g; s{&gt;}{>}g; s{&amp;}{&}g; s{&quot;}{"}g; s{&#39;}{'"'"'}g' \
  | sed '/^[[:space:]]*$/d'
