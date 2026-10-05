#!/bin/sh
# Extract the cell contents of a Microsoft Excel .xlsx file (carrier spec
# workbook) as plain text.
#
# An .xlsx is a ZIP of XML parts. This script walks the workbook in sheet
# order, resolves the shared-string table, and prints every non-empty row as
# its non-empty cells joined by " | ". Each sheet is preceded by a banner
# line "========== <sheet name> ==========". Output goes to stdout.
#
# It uses only the Python 3 standard library (zipfile + ElementTree) — no
# openpyxl or other third-party package is required.
#
# Usage:  xlsx-to-text.sh <input.xlsx>
# Stdin:  ignored.
# Stdout: plain text, one spreadsheet row per line, empty rows trimmed.
# Exit:   0 on success; non-zero if input is missing or not a valid xlsx.

set -eu

if [ $# -ne 1 ]; then
  echo "usage: xlsx-to-text.sh <input.xlsx>" >&2
  exit 1
fi

INPUT="$1"

if [ ! -f "$INPUT" ]; then
  echo "xlsx-to-text: input not found: $INPUT" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "xlsx-to-text: python3 is not on PATH" >&2
  exit 1
fi

python3 - "$INPUT" <<'PYEOF'
import sys, zipfile
import xml.etree.ElementTree as ET


def local(tag):
    """Strip the XML namespace, leaving the bare element/attribute name."""
    return tag.rsplit('}', 1)[-1]


RID = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'

path = sys.argv[1]

try:
    z = zipfile.ZipFile(path)
except zipfile.BadZipFile:
    sys.stderr.write("xlsx-to-text: not a valid .xlsx (bad zip): %s\n" % path)
    sys.exit(1)

names = set(z.namelist())

# Shared-string table. Each <si> may hold one <t> or several <r><t> runs.
shared = []
if 'xl/sharedStrings.xml' in names:
    root = ET.fromstring(z.read('xl/sharedStrings.xml'))
    for si in root:
        shared.append(''.join(
            t.text or '' for t in si.iter() if local(t.tag) == 't'))

# Sheets, in workbook display order, with their relationship id.
wb = ET.fromstring(z.read('xl/workbook.xml'))
sheets = [(el.get('name'), el.get(RID))
          for el in wb.iter() if local(el.tag) == 'sheet']

# Relationship id -> part path.
rels = {}
if 'xl/_rels/workbook.xml.rels' in names:
    for el in ET.fromstring(z.read('xl/_rels/workbook.xml.rels')):
        rels[el.get('Id')] = el.get('Target')


def part_path(target):
    if target.startswith('/'):
        return target.lstrip('/')
    return 'xl/' + target


for name, rid in sheets:
    target = rels.get(rid)
    if not target:
        continue
    sp = part_path(target)
    if sp not in names:
        continue
    print('==========', name, '==========')
    sheet = ET.fromstring(z.read(sp))
    for row in sheet.iter():
        if local(row.tag) != 'row':
            continue
        cells = []
        for c in row:
            if local(c.tag) != 'c':
                continue
            ctype = c.get('t')
            value = None
            for child in c:
                ln = local(child.tag)
                if ln == 'v':
                    value = child.text
                elif ln == 'is':
                    value = ''.join(x.text or '' for x in child.iter()
                                    if local(x.tag) == 't')
            if value is None:
                continue
            if ctype == 's':
                try:
                    value = shared[int(value)]
                except (ValueError, IndexError):
                    value = ''
            value = (value or '').strip()
            if value:
                cells.append(value)
        if cells:
            print(' | '.join(cells))
PYEOF
