#!/usr/bin/env bash
# Decode a SuiteCloud (SDF) savedsearch export into a readable JSON summary of EVERYTHING the
# search form shows — including the tabs the cp_saved_search_rl RESTlet cannot see (Available
# Filters, Audience, Email, the Available-for-Reminders / list / dashboard / menu flags).
#
# usage: bash describe-full.sh <path to exported customsearch_*.xml> [--raw]
#   --raw   also print the decoded nssoc XML to stderr
#
# Needs bash, awk, base64, gunzip and jq. Read-only by design: the <definition> blob is
# checksummed server-side (verified 2026-10-15), so a modified blob cannot be deployed back.
set -euo pipefail

usage() { echo "usage: bash describe-full.sh <exported customsearch_*.xml> [--raw]" >&2; exit 2; }

input_path=""
raw=0
for arg in "$@"; do
  case "$arg" in
    --raw) raw=1 ;;
    -h|--help) usage ;;
    *) [ -z "$input_path" ] && input_path="$arg" || usage ;;
  esac
done
[ -n "$input_path" ] || usage
[ -r "$input_path" ] || { echo "cannot read $input_path" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required (brew install jq / apt install jq)" >&2; exit 1; }

definition=$(sed -n 's/.*<definition>\([^<]*\)<\/definition>.*/\1/p' "$input_path" | head -n 1)
[ -n "$definition" ] || { echo "no <definition> element found — is this a SuiteCloud savedsearch export?" >&2; exit 1; }
wrapper_scriptid=$(sed -n 's/.*<savedsearch scriptid="\([^"]*\)".*/\1/p' "$input_path" | head -n 1)

checksum=${definition%%@*}
rest=${definition#*@}
encoding=${rest%%@*}
rest=${rest#*@}
release=${rest%%@*}
payload=${rest#*@}
[ "$encoding" = "GZC" ] || { echo "unexpected definition encoding '$encoding' (expected GZC); refusing to guess" >&2; exit 1; }

xml=$(printf '%s' "$payload" | base64 --decode | gunzip -c)
[ "$raw" -eq 1 ] && printf '%s\n' "$xml" >&2

# CR/LF inside text values would break line-oriented processing, so they become \001/\002 and the
# awk pass turns them back into JSON "\r" / "\n". After that the whole document is one line.
rows=$(printf '%s' "$xml" | tr '\r\n' '\001\002' | awk -F'<' '
function unescape(s,   out, pos, semi, entity, code, i, c, hex) {
  out = ""
  while ((pos = index(s, "&")) > 0) {
    out = out substr(s, 1, pos - 1)
    s = substr(s, pos)
    semi = index(s, ";")
    if (semi == 0) { out = out s; s = ""; break }
    entity = substr(s, 2, semi - 2)
    s = substr(s, semi + 1)
    if (entity == "lt") out = out "<"
    else if (entity == "gt") out = out ">"
    else if (entity == "quot") out = out "\""
    else if (entity == "apos") out = out "\047"
    else if (entity == "amp") out = out "&"
    else if (substr(entity, 1, 1) == "#") {
      if (substr(entity, 2, 1) == "x" || substr(entity, 2, 1) == "X") {
        hex = tolower(substr(entity, 3)); code = 0
        for (i = 1; i <= length(hex); i++) code = code * 16 + index("0123456789abcdef", substr(hex, i, 1)) - 1
      } else code = substr(entity, 2) + 0
      if (code == 13) out = out "\001"
      else if (code == 10) out = out "\002"
      else if (code > 0 && code < 128) out = out sprintf("%c", code)
      else out = out "&" entity ";"
    }
    else out = out "&" entity ";"
  }
  return out s
}
function jsonstr(s,   out, i, c, n) {
  out = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\") out = out "\\\\"
    else if (c == "\"") out = out "\\\""
    else if (c == "\001") out = out "\\r"
    else if (c == "\002") out = out "\\n"
    else if (c == "\t") out = out "\\t"
    else out = out c
  }
  return "\"" out "\""
}
function attr(tag, name,   pattern) {
  pattern = " " name "=\""
  if (!match(tag, pattern)) return ""
  tag = substr(tag, RSTART + length(pattern))
  return substr(tag, 1, index(tag, "\"") - 1)
}
function section(   s) {
  if (depth >= 4 && name[3] == "SearchDefinition") return name[4]
  if (depth >= 3 && name[3] == "nssoc:dependency") return "dep:" deptype[3]
  return "?"
}
function emit(field, value, present,   d, i, j, sec) {
  i = 0; j = 0
  for (d = 1; d <= depth; d++) if (idx[d] > 0) { if (i == 0) i = idx[d]; else if (j == 0) j = idx[d] }
  sec = section()
  if (present) {
    value = unescape(value)
    if (sec == "descriptor" && field ~ /^FIELD_EMAIL_/) value = unescape(value)   # NetSuite stores these HTML-escaped
    value = jsonstr(value)
  } else value = "null"
  print sec "\t" i "\t" j "\t" field "\t" value
}
{
  depth = 0
  for (f = 2; f <= NF; f++) {
    chunk = $f
    e = index(chunk, ">")
    tag = substr(chunk, 1, e - 1)
    text = substr(chunk, e + 1)
    first = substr(tag, 1, 1)
    if (first == "?" || first == "!") continue
    if (first == "/") {
      if (name[depth] == "Value") emit(valuefield[depth], textbuf, 1)
      depth--
      continue
    }
    selfclosing = (substr(tag, length(tag), 1) == "/")
    if (selfclosing) tag = substr(tag, 1, length(tag) - 1)
    sp = index(tag, " ")
    tagname = sp ? substr(tag, 1, sp - 1) : tag
    if (selfclosing) {
      if (tagname == "Value") { depth++; name[depth] = tagname; idx[depth] = 0; emit(attr(tag, "field"), "", 0); depth-- }
      continue
    }
    depth++
    name[depth] = tagname
    childcount[depth + 1] = 0
    idx[depth] = (tagname == "Record" || tagname == "SearchFilter") ? ++childcount[depth] : 0
    if (tagname == "nssoc:dependency") deptype[depth] = attr(tag, "type")
    if (tagname == "Value") { valuefield[depth] = attr(tag, "field"); textbuf = text }
  }
}')

printf '%s\n' "$rows" | jq -R -s --arg checksum "$checksum" --arg release "$release" --arg wrapper "$wrapper_scriptid" '
  def compact: with_entries(select(.value != null and .value != false and .value != 0 and .value != []));
  def fields: map(select(.value != null)) | map({key: .field, value: .value}) | from_entries;
  def records($section): [ .[] | select(.section == $section) ] | group_by(.i) | map(fields);
  def filters($section): [ .[] | select(.section == $section) ] | group_by(.i) | map(
      (map(select(.j == 0)) | fields) as $d
      | (map(select(.j > 0 and .field == "FIELD_VALUE")) | sort_by(.j) | map(.value)) as $values
      | { field: $d.FIELD_FILTER_NAME, operator: $d.FIELD_ATTRIBUTE, modifier: $d.FIELD_MODIFIER,
          valueType: $d.FIELD_TYPE, formula: $d.FIELD_FORMULA, values: $values,
          not: ($d.FLAG_NOT == "true"), or: ($d.FLAG_OR == "true"),
          leftParens: (($d.FIELD_NUM_LEFT_PARENS // "0") | tonumber),
          rightParens: (($d.FIELD_NUM_RIGHT_PARENS // "0") | tonumber) }
      | compact);
  def labelled($labels; $source): [ $labels | to_entries[] | select($source[.key] != null) | {key: .value, value: ($source[.key] == "true")} ] | from_entries;

  ({ FLAG_PUBLIC: "Public", FLAG_LIST: "Available as List View", FLAG_PORTLET: "Available as Dashboard View",
     FLAG_MACHINE: "Available as Sublist View", FLAG_REMINDER: "Available for Reminders", FLAG_SHOW_LINK: "Show in Menu",
     FLAG_UNRESTRICTED: "Run Unrestricted", FLAG_PREFERRED_LIST: "Default list view for this record type",
     FLAG_PREFERRED_PORTLET: "Default dashboard view", FLAG_PREFERRED_MACHINE: "Default sublist view",
     FLAG_PREFERRED_FORM: "Default search form", FLAG_PREFERRED_RESULTS: "Default results view",
     FLAG_VIEW_AS_REPORT: "Results view: report", FLAG_VIEW_AS_GRAPH: "Results view: graph", FLAG_VIEW_AS_GRID: "Results view: grid",
     FLAG_DISABLE_DRILL_DOWN: "Disable drill-down", FLAG_HIDE_FILTER_DROPDOWNS: "Hide available-filter dropdowns",
     FLAG_AVAILABLE_AS_FEED: "Available as feed", FLAG_AVAILABLE_FOR_PUBLISHING: "Available for publishing",
     FLAG_GLOBAL_EDIT: "Allow inline (global) editing", FLAG_SHOW_AUDIT_TRAIL: "Show audit trail",
     FLAG_HAS_TOTALS: "Show totals", FLAG_INCLUDE_PERIOD_END_TRANSACTIONS: "Include period-end transactions" }) as $flagLabels
  | ({ FLAG_SCHEDULED_ALERT: "Send emails according to schedule",
       FLAG_TRIGGERED_ALERT: "Triggered alert (FLAG_TRIGGERED_ALERT)", FLAG_SEND_ON_UPDATE: "Send on update (FLAG_SEND_ON_UPDATE)",
       FLAG_SCHEDULED_ALERT_SUMMARIES: "Summarize scheduled emails", FLAG_SEND_EMPTY_RESULTS: "Send if no results",
       FLAG_ALERT_ALLOW_SUBSCRIBE: "Allow users to subscribe", FLAG_ALERT_INCLUDE_VIEW_LINK: "Include '"'"'view record'"'"' link",
       FLAG_CSV: "Attach results as CSV", FLAG_EXCEL: "Attach results as Excel", FLAG_PDF: "Attach results as PDF" }) as $emailFlagLabels
  | ({ FIELD_EMAIL_FROM: "From", FIELD_EMAIL_SUBJECT: "Subject", FIELD_EMAIL_BODY: "Body", FIELD_EMAIL_COMMENT: "Comment" }) as $emailFieldLabels
  | ( split("\n") | map(select(length > 0) | split("\t")
        | {section: .[0], i: (.[1] | tonumber), j: (.[2] | tonumber), field: .[3], value: (.[4] | fromjson)}) ) as $rows
  | ($rows | map(select(.section == "descriptor")) | fields) as $desc
  | ($rows | map(select(.section == "dep:Audience")) | fields) as $aud
  | {
      scriptId: $desc.KEY_SCRIPT_ID,
      title: $desc.FIELD_DEFAULT_NAME,
      searchType: $desc.FIELD_SEARCH_TYPE,
      isPublic: ($desc.FLAG_PUBLIC == "true"),
      flags: labelled($flagLabels; $desc),
      audience: (if ($aud | length) == 0 then null else {
        allRoles: ($aud.FLAG_AUDIENCE_ALL_ROLES == "true"), allEmployees: ($aud.FLAG_AUDIENCE_ALL_EMPLOYEES == "true"),
        allCustomers: ($aud.FLAG_AUDIENCE_ALL_CUSTOMERS == "true"), allVendors: ($aud.FLAG_AUDIENCE_ALL_VENDORS == "true"),
        allPartners: ($aud.FLAG_AUDIENCE_ALL_PARTNERS == "true"),
        roleIds: ([($aud.FIELD_AUDIENCE_ROLES // "") | splits("[,[:space:]]+")] | map(select(length > 0))),
        rawFields: $aud } end),
      availableFilters: ($rows | records("availableFilterFields") | map({
        field: .FIELD_NAME, customLabel: .FIELD_CUSTOM_LABEL, showInFooter: (.FLAG_FOOTER == "true"),
        footerMultiSelect: (.FLAG_FOOTER_MULTI_SELECT == "true"), sequence: ((.SEQ_NUMBER // "0") | tonumber) })),
      email: {
        flags: labelled($emailFlagLabels; $desc),
        fields: ([ $emailFieldLabels | to_entries[] | {key: .value, value: $desc[.key]} ] | from_entries),
        specificRecipients: ($rows | records("alertRecipients")),
        recipientsFromResults: ($rows | records("alertRecipientFields")) },
      criteria: ($rows | filters("filters")),
      summaryCriteria: ($rows | filters("summaryFilters")),
      results: ($rows | records("returnFields") | map({
        field: .FIELD_ALIAS, index: ((.FIELD_INDEX // "0") | tonumber), label: .FIELD_LABEL, summaryType: .FIELD_SUMMARY_TYPE,
        function: .FIELD_FUNCTION, formula: .FIELD_FORMULA } | compact)),
      # The NetSuite serializer really spells the sort position FILELD_ORDER (seen in every export
      # so far); FIELD_ORDER is accepted too in case a release ever corrects it. No apostrophes in
      # these comments: the whole jq program is a single-quoted shell string.
      sort: ($rows | records("sortColumns") | map({
        field: .KEY_FIELD, order: ((.FILELD_ORDER // .FIELD_ORDER // "0") | tonumber), descending: (.FLAG_DESCENDING == "true") })),
      maxRows: $desc.MAX_ROWS,
      rawDescriptor: $desc,
      export: { checksum: $checksum, release: $release, scriptIdInWrapper: $wrapper }
    }'
