# pdf-roots.awk — print-type pass of pdf-validate.sh (--printtype). Input: the raw template source; -v printType=<UPPER>.
# Warns when the source reads data NetSuite hands only to other print types, so it would render blank as this one.
# Reports the first match of each signal; FreeMarker comments are blanked first, keeping lines and columns.
function blank_comments(text,   result, opening, closing) {
  result = ""
  while (text != "") {
    if (inComment) {
      closing = index(text, "-->")
      if (!closing) { result = result sprintf("%" length(text) "s", ""); return result }
      result = result sprintf("%" (closing + 2) "s", ""); text = substr(text, closing + 3); inComment = 0
    } else {
      opening = index(text, "<#--")
      if (!opening) return result text
      result = result substr(text, 1, opening - 1); text = substr(text, opening); inComment = 1
    }
  }
  return result
}
function check_signal(signal, line,   pattern_index, column, types) {
  if (reported[signal] || index(" " signalTypes[signal] " ", " " printType " ")) return
  for (pattern_index = 1; pattern_index <= patternCount[signal]; pattern_index++) {
    if (!match(line, signalPattern[signal, pattern_index])) continue
    # A leading boundary character belongs to the pattern, not to the name it guards.
    column = RSTART + (substr(line, RSTART, 1) ~ /[A-Za-z<]/ ? 0 : 1)
    types = signalTypes[signal]; gsub(/ /, " or ", types)
    print "WARN\t" FNR "\t" column "\tnetsuite.roots\tthis template reads " signalShown[signal] ", which NetSuite gives only to " types " templates; as " printType " it would print blank — check the print type"
    reported[signal] = 1
    return
  }
}
function add_signal(shown, types, first_pattern, second_pattern) {
  signalCount++; signalShown[signalCount] = shown; signalTypes[signalCount] = types
  signalPattern[signalCount, 1] = first_pattern; patternCount[signalCount] = 1
  if (second_pattern != "") { signalPattern[signalCount, 2] = second_pattern; patternCount[signalCount] = 2 }
}
BEGIN {
  add_signal("results", "SEARCH", "<#list[[:space:]]+results[[:space:]]+as")
  add_signal("records[…] / startlabel", "SHIPPINGLABEL MAILINGLABEL ITEMLABEL", "(^|[^A-Za-z0-9_.])records\\[", "(^|[^A-Za-z0-9_.])startlabel([^A-Za-z0-9_]|$)")
  add_signal("<#list records> (Print Checks)", "TRANSACTION", "<#list[[:space:]]+records[[:space:]]+as")
  add_signal("salesorder", "PACKINGSLIP", "(^|[^A-Za-z0-9_.])salesorder\\.")
  add_signal("statements", "STATEMENT", "(^|[^A-Za-z0-9_.])statements([^A-Za-z0-9_]|$)", "statement\\.lines")
  add_signal("accounting lines", "GLIMPACT", "accountingtransaction_")
}
{
  line = blank_comments($0)
  for (signal = 1; signal <= signalCount; signal++) check_signal(signal, line)
}
