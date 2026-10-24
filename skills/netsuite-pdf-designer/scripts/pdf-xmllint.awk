# pdf-xmllint.awk — maps xmllint errors back to source line:column for pdf-validate.sh. Input: the branch-blanked copy, then xmllint stderr; -v prologLines.
function open_tag_col(text, name,   col, offset) {
  col = 0; offset = 0
  while (match(substr(text, offset + 1), "<" name "([ \t\r/>]|$)")) { col = offset + RSTART; offset += RSTART }
  return col ? col : 1
}
function emit(rule, at_line, at_col, message) { gsub(/\t/, " ", message); print "ERROR\t" (at_line < 1 ? 1 : at_line) "\t" at_col "\t" rule "\t" message }
# libxml2 cascades after a structural error, so only the first is reported; say so, or a fix looks like the last one.
function emit_structural(rule, at_line, at_col, message) {
  emit(rule, at_line, at_col, message "; this is the first XML structure error, so fix it and run the validator again to see any others")
}
FNR == NR { source[FNR] = $0; next }
match($0, /xmllint\.xml:[0-9]+: [a-z ]*error : /) {
  header = substr($0, RSTART, RLENGTH); message = substr($0, RSTART + RLENGTH)
  sub(/^xmllint\.xml:/, "", header); error_line = (header + 0) - prologLines
  context = ""; caret = ""; getline context; getline caret
  caret_col = index(caret, "^"); context_at = context == "" ? 0 : index(source[error_line], context)
  col = context_at ? context_at + caret_col - 1 : (caret_col ? caret_col : 1)
  if (message ~ /EntityRef|Entity '/) {
    while (col > 1 && substr(source[error_line], col, 1) != "&") col--
    if (match(message, /Entity '[^']+'/)) message = "&" substr(message, RSTART + 8, RLENGTH - 9) "; is not a named entity BFO knows; write &amp; or a numeric reference"
    else message = "bare & (write &amp;): " message
    emit("xml.entity", error_line, col, message); next
  }
  if (structural++) next
  if (match(message, /^Opening and ending tag mismatch: [^ ]+ line [0-9]+ and [^ ]+/)) {
    split(message, words, " "); open_name = words[6]; open_line = words[8] - prologLines
    hint = open_name ~ /^(br|img|hr|link|meta|pbr|pagenumber|totalpages)$/ ? "; empty elements must be self-closed, e.g. <" open_name " />" : ""
    emit_structural("xml.mismatch", open_line, open_tag_col(source[open_line], open_name), "<" open_name "> opened here is closed by </" words[10] "> on line " error_line hint)
  } else if (match(message, /^Premature end of data in tag [^ ]+ line [0-9]+/)) {
    split(message, words, " "); open_line = words[9] - prologLines
    emit_structural("xml.unclosed", open_line, open_tag_col(source[open_line], words[7]), "<" words[7] "> is never closed")
  } else {
    if (match(message, / line [0-9]+/)) message = substr(message, 1, RSTART + 5) (substr(message, RSTART + 6, RLENGTH - 6) - prologLines) substr(message, RSTART + RLENGTH)
    emit_structural("xml.syntax", error_line, col, message)
  }
}
