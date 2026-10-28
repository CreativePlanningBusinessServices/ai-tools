# pdf-freemarker.awk — FreeMarker pass of pdf-validate.sh. Input: data.tsv (B/D rows), then the template.
# Prints findings as TSV, writes the <?xml line number to declarationFile when only FreeMarker precedes it, and writes two copies with the template's lines and columns: strippedFile (FreeMarker spans
# blanked, ${…} as x's, every branch kept, for the BFO pass) and xmlCopyFile (also blanks the bodies of non-first
# branches — <#else>, <#elseif>, later <#case>/<#default>/<#on>, <#recover> — so alternative markup parses in xmllint).
# Macro and function bodies go to macroFile as "M<TAB>startLine<TAB>startCol<TAB>endLine<TAB>endCol" rows.
function blanks(count,   text) { text = ""; while (count > 512) { text = text SPACES; count -= 512 } return text substr(SPACES, 1, count) }
function exes(count,   text) { text = ""; while (count > 512) { text = text EXES; count -= 512 } return text substr(EXES, 1, count) }
function finding(severity, at_line, at_col, rule, message) { print severity "\t" at_line "\t" at_col "\t" rule "\t" message }
function put(text) { out = out text; xmlOut = xmlOut (hiddenLevels ? blanks(length(text)) : text) }
function emit(text) {
  put(mode == "interpolation" ? exes(length(text)) : blanks(length(text)))
  if (mode == "directive") body = body text; else if (mode == "interpolation") expression = expression text
}
# FreeMarker 2.3.23+ accepts camelCase names: elseIf -> elseif (directives), hasContent -> has_content (built-ins)
function camel_to_lower(name, separator) {
  if (name !~ /^[a-z][a-zA-Z0-9]*[A-Z]/) return name
  while (match(name, /[A-Z]/)) name = substr(name, 1, RSTART - 1) separator tolower(substr(name, RSTART, 1)) substr(name, RSTART + 1)
  return name
}
function scan_expression(   ch, name) {
  while (pos <= len) {
    ch = substr(line, pos, 1)
    if (quote != "") {
      if (ch == "\\") { emit(substr(line, pos, 2)); pos += 2; continue }
      if (ch == quote) quote = ""
      emit(ch); pos++; continue
    }
    if (ch == "\"" || ch == "'") { quote = ch; emit(ch); pos++; continue }
    if (ch == "?") {
      if (substr(line, pos + 1, 1) == "?") { emit("??"); pos += 2; continue }
      if (match(substr(line, pos + 1), /^[a-zA-Z_][a-zA-Z0-9_]*/)) {
        name = camel_to_lower(substr(line, pos + 1, RLENGTH), "_")
        if (!(name in builtin) && name !~ /^iso(_utc|_local)?(_h|_m|_ms)?(_nz|_fz)?$/)
          finding("ERROR", FNR, pos, "freemarker.builtin", "?" name " is not a FreeMarker 2.3 built-in; NetSuite fails the render")
      }
    } else if (mode == "interpolation") {
      if (ch == "{") braces++
      else if (ch == "}" && --braces == 0) { check_loop_references(expression); put("x"); pos++; mode = ""; return }
      else if (ch == "<" && substr(line, pos) ~ /^<([\/#@]|[a-zA-Z][a-zA-Z0-9_:.-]*([ \t\r\/>]|$))/) {
        finding("ERROR", startLine, startCol, "freemarker.interpolation", "${ is never closed with }"); mode = ""; return
      }
    } else if (ch == "(") parens++
    else if (ch == ")") parens--
    else if (ch == ">" && parens <= 0) { put(" "); pos++; mode = ""; end_directive(); return }
    emit(ch); pos++
  }
}
function end_directive(   name, parents) {
  if (!closing && match(body, /^(assign|global|local)[ \t\r\n]+[a-zA-Z_][a-zA-Z0-9_]*/)) {
    assignedName = substr(body, RSTART, RLENGTH); sub(/^[a-z]+[ \t\r\n]+/, "", assignedName); assigned[assignedName] = 1
  }
  if (!closing) check_loop_references(body)
  if (kind == "@" || !match(body, /^[a-zA-Z_]+/)) return
  name = camel_to_lower(substr(body, 1, RLENGTH), "")
  if (!(name in directive)) { finding("ERROR", startLine, startCol, "freemarker.directive", "<#" name "> is not a FreeMarker directive"); return }
  if (closing) { close_block(name); return }
  if (name in allowedParents) {
    parents = allowedParents[name]; gsub(/ /, "> or <#", parents)
    if (index(" " allowedParents[name] " ", " " stackName[depth] " ") == 0)
      finding("ERROR", startLine, startCol, "freemarker.misplaced", "<#" name "> must sit directly inside <#" parents ">")
    else if (name ~ /^(case|default|on)$/ && !caseSeen[depth]) caseSeen[depth] = 1
    else if (!alternate[depth]) { alternate[depth] = 1; hiddenLevels++ }
    return
  }
  if (!(name in blockDirective) || body ~ /\/[ \t\r\n]*$/) return
  if (name ~ /^(assign|global|local)$/ && body ~ /=/) return
  depth++; stackName[depth] = name; stackLine[depth] = startLine; stackCol[depth] = startCol; alternate[depth] = 0; caseSeen[depth] = 0
  loopVariables[depth] = name ~ /^(list|items)$/ ? bound_loop_variables(body) : ""
  if (name == "noparse") mode = "noparse"
}
function close_block(name,   level) {
  if (name == "sep") return
  for (level = depth; level > 0 && stackName[level] != name; level--) ;
  if (level == 0) { finding("ERROR", startLine, startCol, "freemarker.stray", "</#" name "> has no matching <#" name ">"); return }
  while (depth > level) {
    finding("ERROR", stackLine[depth], stackCol[depth], "freemarker.unclosed", "<#" stackName[depth] "> is not closed before </#" name "> on line " startLine)
    pop_level()
  }
  pop_level()
}
# A macro or function body is markup out of context (a <tr> defined for a table elsewhere); the BFO pass skips its
# nesting checks inside these ranges.
function pop_level() {
  if (stackName[depth] ~ /^(macro|function)$/) print "M\t" stackLine[depth] "\t" stackCol[depth] "\t" startLine "\t" startCol > macroFile
  loopVariables[depth] = ""
  if (alternate[depth]) hiddenLevels--; depth--
}
# "list seq as item" or "list map as key, value" or "items as item" -> "item" or "key value"
function bound_loop_variables(text,   names) {
  if (!match(text, /[ \t\r\n]as[ \t\r\n]+[a-zA-Z_][a-zA-Z0-9_]*([ \t\r\n]*,[ \t\r\n]*[a-zA-Z_][a-zA-Z0-9_]*)?/)) return ""
  names = substr(text, RSTART, RLENGTH); sub(/^[ \t\r\n]as[ \t\r\n]+/, "", names); gsub(/[ \t\r\n]*,[ \t\r\n]*/, " ", names)
  return names
}
function loop_bound(variable,   level) {
  for (level = depth; level > 0; level--) if (index(" " loopVariables[level] " ", " " variable " ")) return 1
  return 0
}
# Renaming a loop (as item -> as component) and leaving item_index or item?counter behind renders without error in
# NetSuite but silently drops what that expression guarded.
function check_loop_references(text,   rest, reference, variable, before, after) {
  gsub(/"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/, "", text)
  rest = text
  while (match(rest, /[a-zA-Z_][a-zA-Z0-9_]*(_index|_has_next|\?(index|counter|has_next|is_first|is_last|item_parity|item_parity_cap|item_cycle|is_even_item|is_odd_item))/)) {
    before = RSTART > 1 ? substr(rest, RSTART - 1, 1) : ""
    after = substr(rest, RSTART + RLENGTH, 1)
    reference = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    if (before ~ /[a-zA-Z0-9_.]/ || after ~ /[a-zA-Z0-9_]/ || (reference !~ /\?/ && reference in assigned)) continue
    variable = reference; sub(/(_index|_has_next|\?[a-z_]+)$/, "", variable)
    if (!loop_bound(variable))
      finding("WARN", startLine, startCol, "freemarker.loop-variable", reference " needs a loop variable " variable ", but no enclosing <#list> or <#items> binds it (a renamed loop?); NetSuite renders without error and drops what it guards")
  }
}
BEGIN {
  FS = "\t"; SPACES = sprintf("%512s", ""); EXES = SPACES; gsub(/ /, "x", EXES); seekingDeclaration = 1
  split("if list items macro function attempt switch compress escape noescape autoesc noautoesc outputformat noparse assign global local", names, " ")
  for (i in names) blockDirective[names[i]] = 1
  allowedParents["else"] = "if list"; allowedParents["elseif"] = "if"; allowedParents["recover"] = "attempt"
  allowedParents["case"] = "switch"; allowedParents["default"] = "switch"; allowedParents["on"] = "switch"
}
FNR == NR { if ($1 == "B") builtin[$2] = 1; else if ($1 == "D") directive[$2] = 1; next }
{
  line = $0; len = length(line); out = ""; xmlOut = ""; pos = 1; lineText = ""
  while (pos <= len) {
    if (mode == "comment") {
      found = index(substr(line, pos), "-->")
      if (!found) { put(blanks(len - pos + 1)); pos = len + 1 } else { put(blanks(found + 2)); pos += found + 2; mode = "" }
      continue
    }
    if (mode == "noparse") {
      if (!match(substr(line, pos), /<\/#no[pP]arse/)) { put(substr(line, pos)); pos = len + 1 }
      else { put(substr(line, pos, RSTART - 1)); pos += RSTART - 1; mode = "" }
      continue
    }
    if (mode == "directive" || mode == "interpolation") { scan_expression(); continue }
    rest = substr(line, pos)
    if (!match(rest, /<\/?[#@][a-zA-Z_-]|\$\{/)) { put(rest); lineText = lineText rest; break }
    put(substr(rest, 1, RSTART - 1)); lineText = lineText substr(rest, 1, RSTART - 1)
    pos += RSTART - 1; startLine = FNR; startCol = pos; quote = ""
    if (substr(line, pos, 4) == "<#--") { mode = "comment"; put("    "); pos += 4 }
    else if (substr(line, pos, 2) == "${") { mode = "interpolation"; braces = 1; expression = ""; put("xx"); pos += 2 }
    else {
      closing = (substr(line, pos + 1, 1) == "/"); kind = substr(line, pos + 1 + closing, 1)
      mode = "directive"; body = ""; parens = 0; put(blanks(2 + closing)); pos += 2 + closing
    }
  }
  if (mode == "directive") body = body "\n"
  # FreeMarker output drops its own spans and any line holding only FTL tags, so <#ftl …> on a line of
  # its own (NetSuite's standard label templates) or <#assign …><?xml …?> still puts the declaration first.
  if (seekingDeclaration && !(lineText ~ /^[ \t\r]*$/ && lineText != line)) {
    if (lineText ~ /^<\?xml[ \t]/ && (FNR > 1 || line !~ /^<\?xml/)) print FNR > declarationFile
    seekingDeclaration = 0
  }
  print out > strippedFile; print xmlOut > xmlCopyFile
}
END {
  if (mode == "comment") { finding("ERROR", startLine, startCol, "freemarker.comment", "<#-- is never closed with -->"); corrupt = 1 }
  if (mode == "directive") { finding("ERROR", startLine, startCol, "freemarker.tag", "this FreeMarker tag never ends with >"); corrupt = 1 }
  if (mode == "interpolation") finding("ERROR", startLine, startCol, "freemarker.interpolation", "${ is never closed with }")
  for (; depth > 0; depth--) {
    finding("ERROR", stackLine[depth], stackCol[depth], "freemarker.unclosed", "<#" stackName[depth] "> is never closed with </#" stackName[depth] ">")
    if (stackName[depth] ~ /^(macro|function)$/) print "M\t" stackLine[depth] "\t" stackCol[depth] "\t" FNR + 1 "\t1" > macroFile
  }
  if (corrupt) print "corrupt" > corruptFile
}
